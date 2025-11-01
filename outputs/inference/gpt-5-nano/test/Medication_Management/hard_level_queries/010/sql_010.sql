WITH base AS (
  -- Cohort: male, age 61-71, hemorrhagic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND dd.long_title LIKE '%hemorrhagic stroke%'
),
mcs AS (
  -- First-24-hour medication complexity score proxy: distinct drugs prescribed in first 24 hours
  SELECT
    b.hadm_id,
    COUNT(DISTINCT pr.drug) AS mcs24
  FROM base AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = b.subject_id
   AND pr.hadm_id = b.hadm_id
   AND pr.starttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 24 HOUR)
  GROUP BY b.hadm_id
),
readmit AS (
  -- 30-day readmission flag using next admission per patient
  SELECT b.*,
         LEAD(b.admittime) OVER (PARTITION BY b.subject_id ORDER BY b.admittime) AS next_admit
  FROM base AS b
),
final AS (
  SELECT
    r.hadm_id,
    COALESCE(m.mcs24, 0) AS mcs24,
    CAST(TIMESTAMP_DIFF(r.dischtime, r.admittime, SECOND) AS FLOAT64) / 86400.0 AS los_days,
    CASE WHEN r.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mortality,
    CASE WHEN r.next_admit IS NOT NULL
           AND r.next_admit <= TIMESTAMP_ADD(r.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS readmit_30,
    NTILE(5) OVER (ORDER BY COALESCE(m.mcs24, 0)) AS quintile
  FROM readmit AS r
  LEFT JOIN mcs AS m
    ON m.hadm_id = r.hadm_id
)
SELECT
  quintile,
  COUNT(*) AS num_patients,
  AVG(mcs24) AS mean_complexity,
  AVG(los_days) AS avg_los_days,
  AVG(in_hosp_mortality) AS in_hosp_mortality_rate,
  AVG(readmit_30) AS thirty_day_readmission_rate
FROM final
GROUP BY quintile
ORDER BY quintile;