WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days, inclusive
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 67 AND 77
    -- AMI: ICD-9 410% or ICD-10 I21% / I22%
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
          OR (di.icd_version = 9  AND di.icd_code LIKE '410%')
        )
    )
),

-- Part 2: Compute per-admission first-24h medication complexity proxy (MCS)
cohort AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    b.los_days,
    -- first-24h MCS proxy: number of distinct medications started within 24 hours of admission
    COALESCE((
      SELECT COUNT(DISTINCT ph.medication)
      FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
      WHERE ph.subject_id = b.subject_id
        AND ph.hadm_id = b.hadm_id
        AND ph.starttime >= b.admittime
        AND ph.starttime <= TIMESTAMP_ADD(b.admittime, INTERVAL 24 HOUR)
    ), 0) AS mcs,
    -- 30-day readmission indicator (to be computed below)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = b.subject_id
        AND a2.admittime > b.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30
  FROM base b
)

-- Part 3: Assign tertiles and summarize by tertile
SELECT
  tertile,
  COUNT(*) AS admissions,
  MIN(mcs) AS min_mcs,
  MAX(mcs) AS max_mcs,
  AVG(mcs) AS mean_mcs,
  AVG(los_days) AS mean_los_days,
  100 * AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality_percent,
  100 * AVG(CAST(readmit_30 AS INT64)) AS readmission_30d_percent
FROM (
  SELECT
     *,
     NTILE(3) OVER (ORDER BY mcs) AS tertile
  FROM cohort
) t
GROUP BY tertile
ORDER BY tertile;