WITH hf_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 9  AND d.icd_code LIKE '428%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
med_complexity AS (
  SELECT
    ha.subject_id,
    ha.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM hf_admissions ha
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ha.hadm_id = pr.hadm_id
    AND pr.starttime >= ha.admittime
    AND pr.starttime < ha.admittime + INTERVAL 7 DAY
  GROUP BY ha.subject_id, ha.hadm_id
),
los_mort_readmit AS (
  SELECT
    ha.subject_id,
    ha.hadm_id,
    mc.complexity_score,
    TIMESTAMP_DIFF(ha.dischtime, ha.admittime, DAY) AS los_days,
    ha.hospital_expire_flag,
    -- 30-day readmission:
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ha.subject_id
        AND a2.admittime > ha.dischtime
        AND TIMESTAMP_DIFF(a2.admittime, ha.dischtime, DAY) <= 30
    ) THEN 1 ELSE 0 END AS readmit_30d
  FROM hf_admissions ha
  JOIN med_complexity mc
    ON ha.subject_id = mc.subject_id
   AND ha.hadm_id = mc.hadm_id
),
with_quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    los_days,
    hospital_expire_flag,
    readmit_30d,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM los_mort_readmit
)
SELECT
  quintile,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  COUNT(DISTINCT hadm_id) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag)*100, 2) AS in_hosp_mortality_percent,
  ROUND(AVG(readmit_30d)*100, 2) AS readmit_30d_percent
FROM with_quintiles
GROUP BY quintile
ORDER BY quintile;