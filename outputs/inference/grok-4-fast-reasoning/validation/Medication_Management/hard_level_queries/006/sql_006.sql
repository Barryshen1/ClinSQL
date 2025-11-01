WITH first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    first_careunit,
    intime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
cohort_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    fi.stay_id,
    fi.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN first_icu fi
    ON a.subject_id = fi.subject_id AND a.hadm_id = fi.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND (LOWER(fi.first_careunit) LIKE '%surg%' OR fi.first_careunit = 'CSRU')
),
med_complexity AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    ca.stay_id,
    ca.intime,
    COUNT(DISTINCT CASE WHEN di.category = 'Medications' THEN ie.itemid END) AS complexity_score
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ca.stay_id = ie.stay_id
    AND ie.starttime >= ca.intime
    AND ie.starttime < TIMESTAMP_ADD(ca.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  GROUP BY
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    ca.stay_id,
    ca.intime
),
readmissions AS (
  SELECT
    mc.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = mc.subject_id
        AND a2.hadm_id != mc.hadm_id
        AND a2.admittime > mc.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(mc.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d
  FROM med_complexity mc
  WHERE mc.dischtime IS NOT NULL  -- Exclude any incomplete records
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score ASC) AS quintile
  FROM readmissions
)
SELECT
  quintile,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS avg_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS mortality_rate,
  ROUND(
    SUM(CAST(readmit_30d AS INT)) * 1.0 /
    NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END), 0),
    4
  ) AS readmit_rate,
  COUNT(*) AS n_patients
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;