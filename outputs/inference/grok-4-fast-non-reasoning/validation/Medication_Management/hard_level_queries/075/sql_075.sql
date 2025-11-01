WITH base_admissions AS (
  -- Filter male patients aged 58-68
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
),

med_complexity AS (
  -- Compute unique medication count from prescriptions (hospital-wide)
  SELECT 
    ba.*,
    COALESCE(
      (SELECT COUNT(DISTINCT pr.drug)
       FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
       WHERE pr.hadm_id = ba.hadm_id
         AND pr.starttime >= ba.admittime
         AND pr.starttime < TIMESTAMP_ADD(ba.admittime, INTERVAL 72 HOUR)
         AND pr.drug IS NOT NULL
         AND LENGTH(TRIM(pr.drug)) > 0),
      0
    ) AS num_unique_prescriptions
  FROM base_admissions ba
),

first_icu AS (
  -- Get first ICU stay per admission for med counting
  SELECT 
    hadm_id,
    stay_id,
    intime
  FROM (
    SELECT 
      hadm_id,
      stay_id,
      intime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) 
  WHERE rn = 1
),

icu_meds AS (
  -- Add unique ICU medication count (if ICU stay exists), using drug labels
  SELECT 
    mc.*,
    COALESCE(
      (SELECT COUNT(DISTINCT di.label)
       FROM first_icu ficu
       INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
         ON ficu.stay_id = ie.stay_id
       INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
         ON ie.itemid = di.itemid
       WHERE ficu.hadm_id = mc.hadm_id
         AND ie.starttime >= mc.admittime
         AND ie.starttime < TIMESTAMP_ADD(mc.admittime, INTERVAL 72 HOUR)
         AND di.label IS NOT NULL
         AND LENGTH(TRIM(di.label)) > 0),
      0
    ) AS num_unique_icu_meds
  FROM med_complexity mc
),

complexity_scores AS (
  -- Total complexity score (sum distinct counts as proxy)
  SELECT 
    *,
    num_unique_prescriptions + num_unique_icu_meds AS complexity_score,
    NTILE(3) OVER (ORDER BY (num_unique_prescriptions + num_unique_icu_meds)) AS tertile
  FROM icu_meds
),

readmissions AS (
  -- Flag 30-day readmission (self-join for next admission within 30 days)
  SELECT 
    cs.*,
    CASE 
      WHEN cs.dischtime IS NULL THEN 0
      WHEN (
        SELECT COUNT(DISTINCT nexta.hadm_id)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` nexta
        WHERE nexta.subject_id = cs.subject_id
          AND nexta.hadm_id != cs.hadm_id
          AND nexta.admittime >= cs.dischtime
          AND nexta.admittime < TIMESTAMP_ADD(cs.dischtime, INTERVAL 30 DAY)
          AND nexta.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
      ) > 0 THEN 1 
      ELSE 0 
    END AS readmit_30d_flag
  FROM complexity_scores cs
)

-- Final aggregates by tertile
SELECT 
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  ROUND(AVG(complexity_score), 2) AS mean_complexity,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_pct,
  ROUND(
    AVG(CASE WHEN hospital_expire_flag = 0 THEN readmit_30d_flag * 1.0 ELSE NULL END) * 100, 
    2
  ) AS readmit_30d_pct  -- % among survivors only
FROM readmissions
GROUP BY tertile
ORDER BY tertile;