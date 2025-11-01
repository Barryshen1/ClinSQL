WITH hf_admissions AS (
  -- HF admissions for male patients aged 40-50
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
              (di.icd_version = 9 AND di.icd_code LIKE '428%')
              OR
              (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
            )
    )
),
mcs_per_hadm AS (
  -- 7-day medication complexity score per admission: distinct drugs in first 7 days
  SELECT
    h.hadm_id,
    COUNT(DISTINCT p.drug) AS mcs
  FROM hf_admissions AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = h.subject_id
   AND p.hadm_id = h.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= h.admittime
    AND TIMESTAMP_DIFF(p.starttime, h.admittime, DAY) <= 7
  GROUP BY h.hadm_id
),
hf_with_mcs AS (
  -- Attach MCS to HF admissions; default to 0 if no meds found in first 7 days
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    COALESCE(m.mcs, 0) AS mcs
  FROM hf_admissions AS h
  LEFT JOIN mcs_per_hadm AS m
    ON h.hadm_id = m.hadm_id
),
admissions_with_next AS (
  -- Compute the next admission per patient to assess 30-day readmission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),
hf_final AS (
  -- Final per-admission record: includes MCS and readmission flag
  SELECT
    w.hadm_id,
    w.subject_id,
    w.admittime,
    w.dischtime,
    w.hospital_expire_flag,
    w.mcs,
    CASE
      WHEN n.next_admittime IS NULL THEN 0
      WHEN TIMESTAMP_DIFF(n.next_admittime, w.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit30,
    TIMESTAMP_DIFF(w.dischtime, w.admittime, SECOND) / 86400.0 AS los_days
  FROM hf_with_mcs AS w
  LEFT JOIN admissions_with_next AS n
    ON w.subject_id = n.subject_id AND w.hadm_id = n.hadm_id
),
mcs_quintile AS (
  -- Compute quintile per admission by 7-day MCS
  SELECT
    f.*,
    NTILE(5) OVER (ORDER BY f.mcs) AS quintile
  FROM hf_final AS f
)
SELECT
  quintile,
  COUNT(*) AS admission_count,
  MIN(mcs) AS mcs_min,
  MAX(mcs) AS mcs_max,
  AVG(los_days) AS mean_los_days,
  SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)) AS in_hospital_mortality_rate,
  AVG(readmit30) AS thirty_day_readmission_rate
FROM mcs_quintile
GROUP BY quintile
ORDER BY quintile;