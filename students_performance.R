if(!require(DBI)) install.packages("DBI")
if(!require(RPostgres)) install.packages("RPostgres")

library(DBI)
library(RPostgres)

# 1. Connect
con <- dbConnect(RPostgres::Postgres(),
                 dbname = "student_db",
                 host = "localhost",
                 port = 5432,
                 user = "postgres",
                 password = "1979")


# 2. Create tables in SQL using R
# Drop tables if exist (for clean rerun)
dbExecute(con, "DROP TABLE IF EXISTS scores;")
dbExecute(con, "DROP TABLE IF EXISTS students;")

# Recreate tables
dbExecute(con,"
  CREATE TABLE students(
    student_id SERIAL PRIMARY KEY,
    gender TEXT,
    race_ethnicity TEXT,
    parental_education TEXT,
    lunch TEXT,
    test_preparation TEXT
  );")

dbExecute(con,"
  CREATE TABLE scores(
    score_id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(student_id),
    math INTEGER,
    reading INTEGER,
    writing INTEGER
  );")


# 3. Read CSV, split into two data frames
df <- read.csv("c:/users/QDS/R_Projects/student_db/students_performance.csv")

# Change df column names
colnames(df) <- c("gender", "race_ethnicity", "parental_education", 
                  "lunch", "test_preparation", "math", "reading", "writing")

students_df <- df[, 1:5]
scores_df <- df[, 6:8]


# 4. Insert demographics and get IDs:
dbWriteTable(con,
             name = "students", # Table name
             value = students_df, # Data frame
             append = TRUE, # Add to existing table; overwrite = TRUE # Overwrite if table exists
             row.names = FALSE # Skip writing R row names into the table
)

# Check by reading back the data
head(dbReadTable(con, "students"))

# Fetch assigned IDs
n <- nrow(students_df)

query <- paste0("
  SELECT student_id 
  FROM students
  ORDER BY student_id DESC
  LIMIT ", n, ";")

ids <- dbGetQuery(con, query)

scores_df$student_id <- ids$student_id
scores_df <- scores_df[, c("student_id", "math", "reading", "writing")]


# 5. Insert scores
dbWriteTable(con,
             "scores",
             scores_df,
             append = TRUE,
             row.names = FALSE
)

# Check
head(dbReadTable(con, "scores"))


# Query and validate with a join
res <- dbGetQuery(con,
                  "SELECT gender, AVG((math + reading + writing)/3) AS avg_score
                  FROM students JOIN scores USING (student_id)
                  GROUP BY gender")
print(res)

# 6. New tables courses and enrollments
# Drop tables if exist (for clean rerun)
dbExecute(con, "DROP TABLE IF EXISTS courses;")
dbExecute(con, "DROP TABLE IF EXISTS enrollments;")

dbExecute(con,
          " CREATE TABLE courses(
          course_id SERIAL PRIMARY KEY,
          course_name TEXT NOT NULL,
          department TEXT,
          credits TEXT );"
          )

dbExecute(con,
          " CREATE TABLE enrollments(
          enrollment_id SERIAL PRIMARY KEY,
          student_id INTEGER REFERENCES students(student_id),
          course_id INTEGER REFERENCES courses(course_id),
          semester TEXT,
          grade TEXT);"
          )

# 7. Simulate Data in R
# Create course data
courses_df <- data.frame(
  course_name = c("Math 101", "English 101", "Biology 201", "Computer Science 101", "History 101"),
  department = c("Mathematics", "English", "Biology", "Computer Science", "History"),
  credits = c(3, 3, 4, 4, 3)
)

dbWriteTable(con,
             "courses",
             courses_df,
             append = TRUE,
             row.names = FALSE)

dbReadTable(con, "courses")

# Create enrollment data (100 records randomly matched)
set.seed(79)
# Fetch students and courses IDs
student_ids <- dbGetQuery(con, "SELECT student_id FROM students")$student_id
course_ids <- dbGetQuery(con, "SELECT course_id FROM courses")$course_id

# Generate 100 random enrollments
n <- 100
enrollments_df <- data.frame(
  student_id = sample(student_ids, n, replace = TRUE),
  course_id = sample(course_ids, n, replace = TRUE),
  semester = sample(c("Fall 2025", "Spring 2026"), n, replace = TRUE),
  grade = sample(c("A", "B", "C", "D", "F"), n, replace = TRUE, prob = c(0.3, 0.3, 0.2, 0.1, 0.1))
)

dbWriteTable(con,
             "enrollments",
             enrollments_df,
             append = TRUE,
             row.names = FALSE)

head(dbReadTable(con, "enrollments"))


# 8. Practice query in R
# 8.0 SQL JOIN in R
query0 <- "SELECT s.student_id, c.course_name, e.semester, e.grade
          FROM enrollments e
            JOIN students s USING (student_id)
            JOIN courses c USING (course_id)
          LIMIT 10;"

joined <- dbGetQuery(con, query0)
print(joined)

# 8.1 Count students per course
query1 <- "SELECT course_name, count(student_id) AS student_count
          FROM courses c JOIN enrollments e USING (course_id)
          GROUP BY course_name
          ORDER BY student_count DESC;"

students_per_course <- dbGetQuery(con, query1)
students_per_course

# 8.2 Grade distribution per department
query2 <- "SELECT c.department, e. grade, count(*) as grade_count
          FROM courses c JOIN enrollments e USING (course_id)
          GROUP BY c.department, e.grade 
          ORDER BY c. department, grade_count;"

grade_distribution <- dbGetQuery(con, query2)
grade_distribution

# 8.3 GPA calculation
# Convert letter grades to points
# Mapping A = 4, B = 3, C = 2, D = 1, F = 0
query3 <- "SELECT s.student_id, e.grade,
              CASE e.grade
                  WHEN 'A' THEN 4.0
                  WHEN 'B' THEN 3.0
                  WHEN 'C' THEN 2.0
                  WHEN 'D' THEN 1.0
                  ELSE 0.0
              END AS grade_points
          FROM students s JOIN enrollments e USING (student_id);"

grades_and_points <- dbGetQuery(con, query3)
grades_and_points

# Calculate GPA per student
library(tidyverse)
gpa_by_student <- grades_and_points %>%
  group_by(student_id) %>%
  summarize(GPA = round(mean(grade_points, na.rm = TRUE), 2)) %>%
  arrange(desc(GPA))

gpa_by_student
nrow(gpa_by_student)

# 8.4 Visualize average grades by course
query4 <- "SELECT c.course_name,
              AVG(CASE e.grade
                  WHEN 'A' THEN 4.0
                  WHEN 'B' THEN 3.0
                  WHEN 'C' THEN 2.0
                  WHEN 'D' THEN 1.0
                  WHEN 'F' THEN 0.0
              END) AS avg_gpa
          FROM courses c JOIN enrollments e USING (course_id)
          GROUP BY course_id
          ORDER BY avg_gpa DESC;"

avg_gpa_by_course <- dbGetQuery(con, query4)
avg_gpa_by_course

# Visualization
avg_gpa_by_course %>%
  ggplot(aes(reorder(course_name, avg_gpa), avg_gpa)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  coord_flip() +
  labs(title = "Average GPA by Course",
       x = "Courses",
       y = "Average GPA") +
  theme_minimal()


# 8.5 Calculate pass rates by course
# Define passing grades as A, B, or C
query5 <- "SELECT 
              c.course_name,
              COUNT (*) AS total_enrollments,
              COUNT (*) FILTER (WHERE e.grade IN ('A', 'B', 'C')) *100.0 / COUNT(*) AS pass_rate
          FROM enrollments e JOIN courses c USING (course_id)
          GROUP BY c.course_name
          ORDER BY pass_rate DESC;"

pass_rate_by_course <- dbGetQuery(con, query5)

# 8.6 Top 5 performing students by GPA
# Filter only student with 2+ courses 
query6 <- "SELECT 
              s.student_id, 
              COUNT(e.course_id) AS num_courses,
              AVG(CASE e.grade
                    WHEN 'A' THEN 4.0
                    WHEN 'B' THEN 3.0
                    WHEN 'C' THEN 2.0
                    WHEN 'D' THEN 1.0
                    WHEN 'F' THEN 0.0
                    ELSE NULL
                  END) AS gpa
          FROM students s JOIN enrollments e USING (student_id)
          GROUP BY s.student_id
          HAVING COUNT(e.course_id) >= 2
          ORDER BY gpa DESC
          LIMIT 5;"

top_students <- dbGetQuery(con, query6)
top_students

# 8.7 Detect faling students
query7 <- "SELECT s.student_id, e.grade
          FROM students s JOIN enrollments e USING (student_id)
          WHERE e.grade = 'F';"

fail_students <- dbGetQuery(con, query7)

# Detect courses with highest fail rates
query7.1 <- "SELECT 
                c.course_id, 
                c.course_name,
                COUNT(*) AS num_Fs
            FROM courses c JOIN enrollments e USING (course_id)
            WHERE e.grade = 'F'
            GROUP BY c.course_id, e.grade
            ORDER BY num_Fs DESC
            LIMIT 1; "

fail_course <- dbGetQuery(con, query7.1)

# 8.8 Enrollment trends over semesters
# How many enrollments occured in each semester?
query8 <- "SELECT semester, COUNT(*) AS num_enrollments
          FROM enrollments
          GROUP BY semester
          ORDER BY num_enrollments DESC;"

enrollments_trend <- dbGetQuery(con, query8)
enrollments_trend

# Compare Spring vs. Fall terms
enrollments_trend %>%
  ggplot(aes(x = reorder(semester, -num_enrollments), y = num_enrollments)) +
  geom_col(fill = "steelblue") +
  labs(title = "Enrollment Trends by Semester",
       x = "Semester",
       y = "Number of Enrollments") +
  theme_minimal()

# 8.9 Predict GPA using students demographics (Regression)
# Get average GPA per student that enrolled
query9 <- "SELECT 
              s.student_id,
              s.gender,
              s.race_ethnicity,
              s.parental_education,
              s.lunch,
              s.test_preparation,
              AVG(CASE e. grade
                  WHEN 'A' THEN 4.0
                  WHEN 'B' THEN 3.0
                  WHEN 'C' THEN 2.0
                  WHEN 'D' THEN 1.0
                  WHEN 'F' THEN 0.0
                  ELSE NULL
                END) AS gpa
            FROM students s JOIN enrollments e USING (student_id)
            GROUP BY s.student_id, s.gender, s.race_ethnicity, s.parental_education, s.lunch, s.test_preparation
            HAVING COUNT(e.grade) > 0;"

gpa_data <- dbGetQuery(con, query9)
head(gpa_data)

# Fit a linear regression model in R
# Convert categorical variables to factors
gpa_data <- gpa_data %>%
  mutate(
    gender = factor(gender),
    race_ethnicity = factor(race_ethnicity),
    parental_education = factor(parental_education),
    lunch = factor(lunch),
    test_preparation = factor(test_preparation)
  )

# Fit the model
model <- lm(gpa ~ gender + race_ethnicity + parental_education + lunch + test_preparation, data = gpa_data)

# View summary
summary(model)

# Plot the model
plot(model)

# Check Model Performance
# Predicted vs actual plot
gpa_data$predicted <- predict(model)

ggplot(gpa_data, aes(predicted, gpa)) +
  geom_point(alpha = 0.5) +
  geom_abline(color = "red", linetype = "dashed") +
  labs(title = "Predicted vs Actual GPA",
       x = "Predicted GPA",
       y = "Actual GPA") +
  theme_minimal()

# 8.10 Department-level grade analysis
# Which department gives the most As?
query10 <- "SELECT c.department, COUNT(*) AS num_As
            FROM courses c JOIN enrollments e USING (course_id)
            WHERE e.grade = 'A'
            GROUP BY department
            ORDER BY num_As DESC;"

num_As_by_department <- dbGetQuery(con, query10)
head(num_As_by_department, 1)

# Visualize
num_As_by_department %>% 
  ggplot(aes(reorder(department, num_as), num_as)) +
  geom_col(fill = "steelblue") +
  labs(title = "Number of A-Grades by Department",
       x = "Department",
       y = "Number of A-Grades") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# Which department have the hardest grading?
query10.1 <- "SELECT department,
                  AVG(CASE grade
                        WHEN 'A' THEN 4
                        WHEN 'B' THEN 3
                        WHEN 'C' THEN 2
                        WHEN 'D' THEN 1
                        ELSE 0
                    END) AS avg_gpa
              FROM enrollments e JOIN courses c ON e.course_id = c.course_id
              GROUP BY department
              ORDER BY avg_gpa;"

hardest_department <- dbGetQuery(con, query10.1)
head(hardest_department, 1)

# 8.11 Course load analysis per student
# Count how many courses each student took?
query11 <- "SELECT s.student_id, COUNT(*) AS num_courses
            FROM students s JOIN enrollments e USING (student_id)
            GROUP BY student_id
            ORDER BY num_courses DESC"

course_load <- dbGetQuery(con, query11)
course_load

# Correlate course load with GPA
# View gpa_data and course_load to make sure they both have student_id
head(gpa_data)
head(course_load)

# Join these two data frame together, get rid of demographic columns
course_load_vs_gpa <- course_load %>%
  inner_join(gpa_data %>% select(student_id, gpa), by = "student_id")

head(course_load_vs_gpa)    

# Plot Course load vs. GPA
course_load_vs_gpa %>% 
  ggplot(aes(num_courses, gpa)) +
  geom_jitter(width = 0.2, height = 0, alpha = 0.5, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "darkred") +
  labs(title = "Correlation Between Course Load and GPA",
        x = "Number of Courses Taken",
        y = "GPA") +
  theme_minimal()


