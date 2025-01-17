
# setup
setwd("C:/Users/ukavl/OneDrive/Skrivebord/Hult/02_MsBA/08_Text_Analytics/hult_NLP_student/HW/HW2")


# Libraries
library(pacman)
pacman::p_load(tm, lsa, yardstick, ggplot2, rtweet, tidyverse,
               ggthemes, pbapply, wordcloud, plotrix, pROC, text2vec, 
               caret, glmnet, vtreat, MLmetrics, e1071, RTextTools, qdapRegex)


# User Defined Functions and other Options
source('C:/Users/ukavl/OneDrive/Skrivebord/Hult/02_MsBA/08_Text_Analytics//hult_NLP_student/lessons/Z_otherScripts/ZZZ_supportingFunctions.R')
# Custom cleaning function
easyClean<-function(xVec){
  xVec <- removePunctuation(xVec)
  xVec <- stripWhitespace(xVec)
  xVec <- tolower(xVec)
  return(xVec)
}
options(stringsAsFactors = FALSE, scipen = 999)
Sys.setlocale('LC_ALL','C')


# Importing Data
training = read.csv("student_tm_case_training_data.csv")


# EDA

# Looking at first five rows
head(training, 5)


# Checking classification target
table(training$label)


# Splitting dataset
# creating dataset without emojis
training$rawText = gsub("[^\x01-\x7F]", "", training$rawText) 
training$rawText = rm_url(training$rawText) 

# subsetting data on political topics and transforming it back to matrix
pol_text   = training[grep(1, training$label),]
pol_text   = as.data.frame(pol_text)

# subsetting data on non-political topics and transforming it back to matrix
other_text = training[grep(0, training$label),]
other_text = as.data.frame(other_text)


# Creating and Cleaning Corpuses
# declearing stopwords
stops = c(stopwords("smart"), "rt")

# creating corpuses
all_corpus   = VCorpus(VectorSource(training$rawText))
pol_corpus   = VCorpus(VectorSource(pol_text$raw))
other_corpus = VCorpus(VectorSource(other_text$rawText))

# celaning corpuses
all_corpus   = cleanCorpus(all_corpus, stops)
pol_corpus   = cleanCorpus(pol_corpus, stops)
other_corpus = cleanCorpus(other_corpus, stops)

# creating document term matrix
all_DTM      = DocumentTermMatrix(all_corpus)
pol_DTM      = DocumentTermMatrix(pol_corpus)
other_DTM    = DocumentTermMatrix(other_corpus)

# storing as matrix
all_DTMm     = as.matrix(all_DTM)
pol_DTMm     = as.matrix(pol_DTM)
other_DTMm   = as.matrix(other_DTM)



# VISUAL EDA

# Frewquency Plot
# summarizing all columns
topTerms = colSums(all_DTMm)

# storing as dataframe
topTerms = data.frame(terms = colnames(all_DTMm), freq = topTerms)

# removing row names
rownames(topTerms) = NULL

# filtering out words of small values
topWords = subset(topTerms, topTerms$freq >= 25)

# order in increasing value
topWords = topWords[order(topWords$freq, decreasing = F),]


topWords$terms = factor(topWords$terms,
                        unique(as.character(topWords$terms)))

# display plot
topWords %>% 
  ggplot(data = ., aes(x = terms, y = freq))+
  geom_bar(stat = "identity", fill = "darkblue") + 
  coord_flip()+ 
  theme_gdocs() +
  geom_text(aes(label = freq), colour = "white", hjust = 1.25, size = 3.0)


# Commonality Plot
# unlisting content
pol   = unlist(pblapply(pol_corpus, content))
other = unlist(pblapply(other_corpus, content))

# collapsing content
pol   = paste(pol, collapse = " ")
other = paste(other, collapse = " ")

# combining datasets
all_tweets      = c(pol, other)

# corpus to tdmm
all_tweets      = VCorpus(VectorSource(all_tweets))
all_tweets_TDM  = TermDocumentMatrix(all_tweets)
all_tweets_TDMm = as.matrix(all_tweets_TDM)

# giving column names
colnames(all_tweets_TDMm) = c("political","other")

# displaying plot
commonality.cloud(all_tweets_TDMm, 
                  max.words = 100, 
                  random.order = FALSE,
                  colors = "purple",
                  scale=c(3.5,0.25))


# Comparison Plot
# declaring tf as weighting
ctrl                 = list(weighting = "Tf")

# tdm with weighting
comp_all_tweets_TDM  = TermDocumentMatrix(all_tweets, ctrl)
comp_all_tweets_TDMm = as.matrix(comp_all_tweets_TDM)

# column names
colnames(comp_all_tweets_TDMm) = c("political","other")

# display plot
comparison.cloud(comp_all_tweets_TDMm, 
                 max.words = 75, 
                 random.order = FALSE,
                 title.size = 1,
                 colors = brewer.pal(ncol(comp_all_tweets_TDMm),"Dark2"),
                 scale = c(3,0.5))


# Pyramid Plot
# transforming into dataframe
tweets_df = data.frame(all_tweets_TDMm)

# getting terms into own column and deleting row names
tweets_df$terms = rownames(tweets_df)
rownames(tweets_df) = NULL

# creating a column with absolute difference
tweets_df$diff = abs(tweets_df$political - tweets_df$other)

# ordering increasingly
tweets_df = tweets_df[order(tweets_df$diff, decreasing = TRUE),]
# selecting top 35
top35 = tweets_df[1:35,]

# Pyarmid Plot
pyramid.plot(lx         = top35$political, 
             rx         = top35$other,
             labels     = top35$terms,  
             top.labels = c("Political", "TERMS", "Other"),
             gap        = 40,
             main       = "Words in Common", 
             unit       = 'Word Frequency') 



# CLASSIFICATION MODELS

## Elastic Net

# Sampling the Data
# setting sample size
set.seed(1234)
idx = sample(1:nrow(training), 0.8*nrow(training))
EN_train = training[idx,]
EN_val   = training[-idx,]


# Preparing the Data
# cleaning training set
EN_train$rawText = easyClean(EN_train$rawText)

# iterator to make vocabulary
iterMaker        = itoken(EN_train$rawText,
                          preprocess_function = list(tolower),
                          progressbar = TRUE)

# vocabulary
txtVoc           = create_vocabulary(iterMaker, stopwords = c(stopwords("SMART"), "rt"))

# pruning to shrink dtm
prunedtxtVoc     = prune_vocabulary(txtVoc,
                                    term_count_min = 10,
                                    doc_proportion_min = 0.001,
                                    doc_proportion_max = 0.5)

# declearing dtm vectors
vectorizer = vocab_vectorizer(prunedtxtVoc)

# combining vocabulary function and pruned text function to make dtm
EN_train_DTM = create_dtm(iterMaker, vectorizer)


### Training

# Fitting the training data
EN_train_fit = cv.glmnet(EN_train_DTM,
                         y = as.factor(EN_train$label),
                         alpha = 0.01,
                         family = "binomial",
                         type.measure = "auc",
                         nfolds = 5,
                         intercept = FALSE)


# Predicting the training data
EN_train_pred = predict(EN_train_fit,
                        EN_train_DTM,
                        type = "class",
                        s = EN_train_fit$lambda.min)


#### Accuracy

# Confusion Matrix for The Elastic Net Training Set
table(EN_train_pred, EN_train$label)


### Validating

# Preparing the testing data
# tokenizing new data
val_iter = itoken(EN_val$rawText,
                  tokenizer = word_tokenizer)
# dtm
EN_val_DTM = create_dtm(val_iter, vectorizer)


# Predicting the testing data
EN_val_pred  = predict(EN_train_fit,
                       EN_val_DTM,
                       type = "class",
                       s = EN_train_fit$lambda.min)


#### Accuracy

# Creating Confusion Matrix for Elastic Net
# calculating confmat
EN_confMat = table(EN_val_pred, EN_val$label)

# display confmat
EN_confMat


# Plotting Confusion Matrix for Elastic Net
# display confusion matrix as plot
autoplot(conf_mat(EN_confMat))


# Summary for Elastic Net
# display confusion matrix as plot
metrics = summary(conf_mat(EN_confMat))

# removing "estimator binary"
metrics = metrics[,-2]

# renaming columns
colnames(metrics) =c("Metric","Elastic Net")

# display summary
metrics


# ROC for Elastic Net
# creating roc
EN_roc = roc((EN_val$label), as.numeric(as.character(EN_val_pred)))

# displaying roc
plot(EN_roc, col="blue", main="BLUE = EN",adj=0.5)


## Latent Sentiment Analysis for Generalized Linear Model

# Creating a TDM
class_TDM = TermDocumentMatrix(all_corpus, 
                               control = list(weighting = weightTf))

# creating lsa with 50 sentiments
lsaTDM = lsa(class_TDM, 50)


# Transforming to DataFrame
# transforming into df
docVectors = as.data.frame(lsaTDM$dk)

# appending target
docVectors$yTarget = training$label


# Train/Test Split
# training set
GLM_train = docVectors[idx,]
# validation set
GLM_val   = docVectors[-idx,]


### Training

# Fit & Predict the Generalized Linear Model
# Fitting the training data
GLM_fit        = glm(yTarget~., GLM_train, family = "binomial")

# predicting the training data
GLM_pred_train = predict(GLM_fit, GLM_train, type = "response")


#### Accuracy

# AUC for Training Set
# creating vector of percentage cutoff
cut = c(1:100)/100

# calling empty vector
train_aucs = vector(mode = "double", length = length(cut))

# for loop to go through every cutoff
for(i in seq_along(1:length(cut))){
  # declearing yhat for each cutoff
  train_yHat = ifelse(GLM_pred_train >= cut[i],1,0)
  # appending auc for each cutoff
  train_aucs[i] = auc((GLM_train$yTarget), train_yHat)
}
#transform into df
decide = as.data.frame(cbind(cut, train_aucs))

# plotting data
decide %>% 
  ggplot(data = .)+
  geom_line(aes(x = cut, y = train_aucs), color = "blue")


# Confusion Matrix for Training Set
# making a confusion matrix, keeping it on .5 for now
table((ifelse(GLM_pred_train >= 0.5,1,0)), GLM_train$yTarget)


### Validating

# Predicting the Testing Set
# predicting the test data
GLM_pred_val   = predict(GLM_fit, GLM_val, type = "response")


####Accuracy

# Checking different Cutoff rates for test set
# declare empty vector for test auc
test_aucs = vector(mode = "double", length = length(cut))
# repeat of loop on line 344
for(i in seq_along(1:length(cut))){
  test_yHat = ifelse(GLM_pred_val >= cut[i],1,0)
  test_aucs[i] = auc((GLM_val$yTarget), test_yHat)
}

# attaching new data
decide = cbind(decide, test_aucs)

# displaying plot
decide %>% 
  ggplot(data = .)+
  geom_line(aes(x = cut, y = test_aucs), color = "red")+
  geom_line(aes(x = cut, y = train_aucs), color = "blue")+
  labs(x = "cutoff point", y = "AUC-score")


# Creating Confusion Matrix for GLM
# defining cutoff level
GLM_yHat    = ifelse(GLM_pred_val >= 0.5,1,0)

# making a confusion matrix
GLM_confMat = table(GLM_yHat, GLM_val$yTarget)

# display confusion matrix
GLM_confMat


# Plotting Confusion Matrix for GLM
# display confusion matrix as plot
autoplot(conf_mat(GLM_confMat))


# Summary for the GLM model
# display confusion matrix as plot
glm_metrics = summary(conf_mat(GLM_confMat))

# storing column names i want to reuse
x = colnames(metrics)

# binding together old and new df
metrics = cbind(metrics, glm_metrics$.estimate)

# giving colnames
colnames(metrics) = c(x,"GLM")

# display metrics
metrics


# ROC for Elastic Net and GLM
# caclutaing roc for GLM
GLM_roc = roc((GLM_val$yTarget), GLM_yHat)

# plotting both GLM and EN roc
plot(EN_roc, col = "blue", main = "BLUE = EN, RED = GLM",adj=0.5)
plot(GLM_roc, add = TRUE, col = "red")


## Latent Sentiment Analysis for Bayesian

# Making the dataset for Bayesian
# creating bayesian set
BAY_train = GLM_train
BAY_val   = GLM_val
BAY_train$yTarget = as.factor(BAY_train$yTarget)
BAY_val$yTarget   = as.factor(BAY_val$yTarget)


### Training

# Fitting and Predicting for the Bayesian model
# fitting the training data
BAY_fit = naiveBayes(yTarget ~ ., data = BAY_train, family = "binomial")

# predicting the traning data
BAY_train_pred = predict(BAY_fit, BAY_train)


#### Accuracy

# Confusion Matrix for the Bayesian Training Set
# quick table
table(BAY_train_pred, BAY_train$yTarget)


### Validating

# Fitting The Bayesian Validation Set
# predicting the training data
BAY_val_pred = predict(BAY_fit, BAY_val)


#### Accuracy

# Creating Confusion Matrix for Bayesian Model
# calculating confmat
BAY_confMat  = table(BAY_val_pred, BAY_val$yTarget)

# display confmat
BAY_confMat


# Plotting Confusion matrix for Bayesian Model
# plotting confmat
autoplot(conf_mat(BAY_confMat))


# Summary for the Bayesian Model
# calling summary
bay_metrics = summary(conf_mat(BAY_confMat))

# storing old colnames
x = colnames(metrics)

# binding together old summary with new
metrics = cbind(metrics, bay_metrics$.estimate)

# setting colnames
colnames(metrics) = c(x, "Bayesian")

# display summaries
metrics


# ROC for Elastic Net and GLM and Bayesian
# calc roc
BAY_roc = roc((as.numeric(BAY_val$yTarget)), as.numeric(BAY_val_pred))

# plotting roc for EN, GLM and BAYESIAN
plot(EN_roc, col = "blue", main = "BLUE = EN, RED = GLM, GREEN = BAYESIAN",adj=0.5)
plot(GLM_roc, add = TRUE, col = "red")
plot(BAY_roc, add = TRUE, col = "green")


# TEST SET

# Import Test Set
# importing test set
test_set = read.csv("student_tm_case_score_data.csv")

# cleaning up test set
test_set$rawText = rm_url(test_set$rawText)
test_set$rawText = gsub("[^\x01-\x7F]", "", test_set$rawText)


# Create and Clean Corpus for Test Set
# creating corpus
test_corpus = VCorpus(VectorSource(test_set$rawText))

# celaning corpus
test_corpus = cleanCorpus(test_corpus, stops)


# LSA for Test Set
test_TDM = TermDocumentMatrix(test_corpus, 
                              control = list(weighting = weightTf))

# declaring lsa with 50 sentiments
lsa_test_TDM = lsa(test_TDM, 50)


## Generalized Linear Model

# Predicting on the Test Set with GLM
# extracting info from lsa data
GLM_test        = as.data.frame(lsa_test_TDM$dk)

# predicting 
GLM_pred_test   = as.data.frame(predict(GLM_fit, GLM_test, type = "response"))

# giving new colname to dataset
colnames(GLM_pred_test) = "GLM_Prediction"

# declearing cutoffpoint
GLM_pred_test$GLM_Prediction = ifelse(GLM_pred_test$GLM_Prediction >= 0.5,1,0)

# table of tweets in each cat
table(GLM_pred_test)


# Combining the Predictions with the Dataset
# combining test data and calssification values
test_set = cbind(test_set, GLM_pred_test)


## Bayesian

# Predicting on the Test Set with Bayesian
# declaring bay data
BAY_test        = GLM_test

# predicting and storing as df
BAY_pred_test   = as.data.frame(predict(BAY_fit, BAY_test))

# changing colname
colnames(BAY_pred_test) = "BAY_Prediction"

# table of tweets in each cat
table(BAY_pred_test)


# Combining the Bayesian Predictions with the Dataset
# combining dataset
test_set = cbind(test_set, BAY_pred_test)


