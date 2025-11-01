WITH hemorrhagic_admissions AS (
  -- admissions for male patients age 61-71 with an ICD-10 hemorrhagic stroke diagnosis
  SELECT DISTINCT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         p.gender,
         p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    -- ICD-10 hemorrhagic stroke codes: I60*, I61*, I62*
    AND d.icd_version = 10
    AND (
      LOWER(d.icd_code) LIKE 'i60%' OR
      LOWER(d.icd_code) LIKE 'i61%' OR
      LOWER(d.icd_code) LIKE 'i62%'
    )
),

med_first24 AS (
  -- medication complexity score in first 24 hours after admission
  SELECT ha.subject_id,
         ha.hadm_id,
         ha.admittime,
         ha.dischtime,
         ha.hospital_expire_flag,
         ha.anchor_age,
         -- count distinct medications prescribed in first 24 hours (prefer formulary code)
         COALESCE(med_count.count_distinct_med, 0) AS complexity_score
  FROM hemorrhagic_admissions ha
  LEFT JOIN (
    SELECT p.hadm_id,
           COUNT(DISTINCT COALESCE(p.formulary_drug_cd, LOWER(p.drug))) AS count_distinct_med
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    -- only consider prescriptions with a starttime in the first 24 hours after the admission
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.hadm_id = a.hadm_id
    WHERE p.starttime IS NOT NULL
      AND p.starttime >= a.admittime
      AND p.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    GROUP BY p.hadm_id
  ) med_count
    ON ha.hadm_id = med_count.hadm_id
),

with_quintile AS (
  -- assign quintiles based on complexity_score
  SELECT *,
         NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM med_first24
),

readmissions AS (
  -- identify 30-day readmissions for each index admission (only admissions after the index discharge)
  SELECT wq.hadm_id AS index_hadm_id,
         MAX(CASE WHEN r.admittime > wq.dischtime
                      AND r.admittime <= TIMESTAMP_ADD(wq.dischtime, INTERVAL 30 DAY)
                  THEN 1 ELSE 0 END) AS has_30d_readmit_any
  FROM with_quintile wq
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON wq.subject_id = r.subject_id
       AND r.hadm_id != wq.hadm_id
  GROUP BY wq.hadm_id
)

SELECT
  q.quintile,
  COUNT(1) AS n_patients,
  ROUND(AVG(q.complexity_score), 3) AS mean_complexity_score,
  ROUND(AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, SECOND) / 86400.0), 3) AS avg_los_days,
  ROUND(AVG(CAST(q.hospital_expire_flag AS FLOAT64)), 4) AS in_hospital_mortality_rate,
  -- 30-day readmission rate among those discharged alive:
  -- numerator = count of index admissions with a 30-day readmission and hospital_expire_flag = 0
  -- denominator = count of index admissions with hospital_expire_flag = 0
  CASE
    WHEN SUM(CASE WHEN q.hospital_expire_flag = 0 THEN 1 ELSE 0 END) = 0 THEN NULL
    ELSE ROUND(
      SAFE_DIVIDE(
        SUM(CASE WHEN q.hospital_expire_flag = 0 AND COALESCE(r.has_30d_readmit_any, 0) = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN q.hospital_expire_flag = 0 THEN 1 ELSE 0 END)
      ), 4)
  END AS readmit_30d_rate_among_discharged_alive
FROM with_quintile q
LEFT JOIN readmissions r
  ON q.hadm_id = r.index_hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;