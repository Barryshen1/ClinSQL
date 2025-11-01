WITH transplant_admissions AS (
  -- Step 1: Identify male inpatients aged 43-53 with a transplant diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(dd.long_title) LIKE '%transplant%'
      OR LOWER(dd.long_title) LIKE '%graft%'
      OR LOWER(dd.long_title) LIKE '%transplanted%'
      OR LOWER(dd.long_title) LIKE '%transplantation%'
    )
),
index_admissions AS (
  -- Remove duplicate admissions per patient (in case of multiple transplant diagnoses)
  SELECT DISTINCT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM transplant_admissions
),
med_complexity AS (
  -- Step 3: Compute medication complexity score for first 7 hospital days
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    -- LOS in days
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) AS los,
    -- Medication complexity score: count of unique drugs ordered in first 7 days
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM
    index_admissions ia
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON ia.subject_id = pr.subject_id
      AND ia.hadm_id = pr.hadm_id
      AND pr.starttime >= ia.admittime
      AND pr.starttime < LEAST(DATETIME_ADD(ia.admittime, INTERVAL 7 DAY), ia.dischtime)
  GROUP BY
    ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.hospital_expire_flag
),
readmissions AS (
  -- Step 6: 30-day readmission flag
  SELECT
    m.subject_id,
    m.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = m.subject_id
          AND a2.hadm_id != m.hadm_id
          AND a2.admittime > m.dischtime
          AND a2.admittime <= DATETIME_ADD(m.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM med_complexity m
),
final AS (
  -- Combine all metrics
  SELECT
    m.*,
    r.readmit_30d
  FROM med_complexity m
  LEFT JOIN readmissions r
    ON m.subject_id = r.subject_id AND m.hadm_id = r.hadm_id
),
quartiles AS (
  -- Step 7: Stratify by medication complexity score quartiles
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS med_complexity_quartile
  FROM final
)
-- Step 8: Aggregate per quartile
SELECT
  med_complexity_quartile AS quartile,
  COUNT(*) AS n,
  ROUND(AVG(med_complexity_score), 2) AS mean_med_complexity_score,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS in_hospital_mortality_rate,
  ROUND(AVG(CAST(readmit_30d AS FLOAT64)), 3) AS readmission_30d_rate
FROM quartiles
GROUP BY med_complexity_quartile
ORDER BY quartile;