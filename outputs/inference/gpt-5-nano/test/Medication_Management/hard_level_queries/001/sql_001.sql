WITH filtered_admissions AS (
  -- Cohort: female, age 76-86, cardiac arrest diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dic
    ON dic.subject_id = a.subject_id AND dic.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON did.icd_code = dic.icd_code AND did.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(did.long_title) LIKE '%cardiac arrest%'
),
admissions_with_meds AS (
  -- Medication complexity proxy: distinct drugs started within first 7 days
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.hospital_expire_flag,
    f.los_days,
    COALESCE(COUNT(DISTINCT pr.drug), 0) AS complexity_score
  FROM filtered_admissions AS f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = f.subject_id
   AND pr.hadm_id = f.hadm_id
   AND pr.starttime >= f.admittime
   AND pr.starttime <= TIMESTAMP_ADD(f.admittime, INTERVAL 7 DAY)
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.hospital_expire_flag,
    f.los_days
),
mortality_readmission AS (
  -- In-hospital mortality and 30-day readmission flag per admission
  SELECT
    a.*,
    CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime > a.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30
  FROM admissions_with_meds AS a
),
quintiled AS (
  -- Stratify by medication complexity (first 7 days) into quintiles
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS med_complexity_quintile
  FROM mortality_readmission
)
SELECT
  med_complexity_quintile AS quintile,
  COUNT(*) AS patient_count,
  AVG(complexity_score) AS avg_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_days) AS avg_los_days,
  MIN(los_days) AS min_los_days,
  MAX(los_days) AS max_los_days,
  100.0 * AVG(in_hospital_mortality) AS in_hospital_mortality_pct,
  100.0 * AVG(readmit_30) AS readmission_30_pct
FROM quintiled
GROUP BY med_complexity_quintile
ORDER BY quintile;