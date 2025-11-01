WITH eligible_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
),
admissions_with_stroke AS (
  SELECT DISTINCT ea.subject_id, ea.hadm_id
  FROM eligible_admissions ea
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.subject_id = ea.subject_id
      AND di.hadm_id = ea.hadm_id
      AND di.icd_version = 10
      AND di.icd_code LIKE 'I61%'
  )
),
admissions_with_copd AS (
  SELECT DISTINCT ea.subject_id, ea.hadm_id
  FROM eligible_admissions ea
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.subject_id = ea.subject_id
      AND di.hadm_id = ea.hadm_id
      AND di.icd_version = 10
      AND di.icd_code = 'J44.1'
  )
)
SELECT
  PERCENTILE_CONT(hospital_los, 0.25) AS los_q1,
  PERCENTILE_CONT(hospital_los, 0.75) AS los_q3,
  (PERCENTILE_CONT(hospital_los, 0.75) - PERCENTILE_CONT(hospital_los, 0.25)) AS los_iqr
FROM eligible_admissions ea
INNER JOIN admissions_with_stroke aws ON ea.subject_id = aws.subject_id AND ea.hadm_id = aws.hadm_id
INNER JOIN admissions_with_copd awc ON ea.subject_id = awc.subject_id AND ea.hadm_id = awc.hadm_id;