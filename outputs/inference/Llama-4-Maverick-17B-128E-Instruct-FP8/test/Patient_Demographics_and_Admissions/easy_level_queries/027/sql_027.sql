WITH first_admissions AS (
  SELECT p.subject_id, 
         p.anchor_age,
         a.admittime, 
         a.dischtime,
         ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 77 AND 87
),
los AS (
  SELECT subject_id, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM first_admissions
  WHERE admission_rank = 1
)
SELECT 
  APPROX_QUANTILES(length_of_stay, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(length_of_stay, 100)[OFFSET(75)] AS q3
FROM los;