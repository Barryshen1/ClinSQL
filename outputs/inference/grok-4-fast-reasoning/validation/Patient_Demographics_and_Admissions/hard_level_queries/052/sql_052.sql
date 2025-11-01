WITH patients AS (
  SELECT subject_id, gender, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions AS (
  SELECT 
    a.*,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients p USING (subject_id)
  WHERE a.insurance = 'Medicare'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
),
diagnoses AS (
  SELECT subject_id, hadm_id, icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = '1'
),
index_admissions AS (
  SELECT a.*, d.icd_version
  FROM admissions a
  INNER JOIN diagnoses d USING (subject_id, hadm_id)
  WHERE ((d.icd_version = '10' AND d.icd_code LIKE 'K85%')
     OR (d.icd_version = '9' AND d.icd_code = '5770'))
),
all_admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
index_cohort AS (
  SELECT 
    ia.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM all_admissions aa
        WHERE aa.subject_id = ia.subject_id
          AND aa.hadm_id != ia.hadm_id
          AND aa.admittime > ia.dischtime
          AND aa.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
          AND aa.dischtime IS NOT NULL
      ) THEN 1 ELSE 0 
    END AS readmitted_flag
  FROM index_admissions ia
)
SELECT 
  COUNTIF(readmitted_flag = 1) * 1.0 / COUNT(*) AS readmission_rate,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM index_cohort WHERE readmitted_flag = 1) AS median_los_readmitted_days,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM index_cohort WHERE readmitted_flag = 0) AS median_los_non_readmitted_days,
  COUNTIF(los > 9) * 1.0 / COUNT(*) AS pct_stays_gt_9_days
FROM index_cohort;