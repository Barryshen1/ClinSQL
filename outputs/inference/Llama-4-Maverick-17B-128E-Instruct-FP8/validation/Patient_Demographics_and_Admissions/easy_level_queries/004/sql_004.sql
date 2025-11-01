WITH 
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 70 AND 80
),
first_admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM female_patients)
),
aki_admissions AS (
  SELECT fa.hadm_id, fa.admittime, fa.dischtime
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE fa.admission_rank = 1 AND dicd.long_title LIKE '%Acute kidney failure%'
),
los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM aki_admissions
)
SELECT STDDEV(length_of_stay) AS sd_los
FROM los;