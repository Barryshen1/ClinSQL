WITH patients_40_50_male AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age >= 40
    AND anchor_age <= 50
),
stroke_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'I61%'
),
stroke_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_40_50_male p ON a.subject_id = p.subject_id
  JOIN stroke_diagnoses s ON a.hadm_id = s.hadm_id
),
abnormal_labs_72h AS (
  SELECT le.hadm_id, le.labevent_id
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN stroke_admissions sa ON le.hadm_id = sa.hadm_id
  WHERE le.charttime >= sa.admittime
    AND le.charttime <= DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
    AND LOWER(le.flag) = 'abnormal'
),
instability_score AS (
  SELECT hadm_id, COUNT(*) AS abnormal_lab_count
  FROM abnormal_labs_72h
  GROUP BY hadm_id
),
quartiles AS (
  SELECT 
    sa.hadm_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY inst.abnormal_lab_count) AS instability_quartile
  FROM stroke_admissions sa
  JOIN instability_score inst ON sa.hadm_id = inst.hadm_id
)
SELECT
  instability_quartile,
  COUNT(*) AS admission_count,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
GROUP BY instability_quartile
ORDER BY instability_quartile;