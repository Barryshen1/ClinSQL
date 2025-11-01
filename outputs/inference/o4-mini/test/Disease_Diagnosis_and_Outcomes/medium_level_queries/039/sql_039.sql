WITH ami_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.anchor_age,
    p.gender,
    -- Compute LOS in days
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Require at least one AMI diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '410%')
        OR (icd_version = 10 AND icd_code LIKE 'I21%')
    ) ami_dx
      ON a.hadm_id = ami_dx.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    -- Exclude any shock or respiratory failure diagnosis in this admission
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND (
             dx.icd_code LIKE '7855%'       -- shock
             OR dx.icd_code IN ('518.81','518.82','518.84')  -- resp failure
          ))
          OR (dx.icd_version = 10 AND (
             dx.icd_code LIKE 'R57%'        -- shock
             OR dx.icd_code LIKE 'J96%'     -- resp failure
          ))
        )
    )
),

analysis_prep AS (
  SELECT
    *,
    -- LOS bucket
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8         THEN '8+'
      ELSE '0'                    -- edge if same-day discharge
    END AS los_bucket,
    -- Urgency bucket
    CASE
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS urgency
  FROM ami_cohort
),

agg AS (
  SELECT
    los_bucket,
    urgency,
    COUNT(*) AS n_patients,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    -- median time-to-death in days among those who died
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(deathtime, admittime, DAY),
      2
    )[OFFSET(1)] AS median_t2d_days
  FROM analysis_prep
  GROUP BY los_bucket, urgency
)

SELECT
  los_bucket,
  urgency,
  n_patients,
  n_deaths,
  ROUND(100.0 * n_deaths / n_patients, 1) AS mortality_pct,
  median_t2d_days
FROM agg
ORDER BY
  los_bucket,
  urgency;