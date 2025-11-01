WITH hemorrhagic_adms AS (
  -- 1. Filter admissions for male patients age 89–99 with hemorrhagic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%hemorrhag%'
    )
),
med_counts AS (
  -- 2. Count distinct drugs in first 7 days of each admission
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    COUNT(DISTINCT p.drug) AS med_count
  FROM
    hemorrhagic_adms AS h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON h.hadm_id = p.hadm_id
    AND p.starttime >= h.admittime
    AND p.starttime < TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag
),
with_quintile AS (
  -- 3. Assign quintiles based on med_count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM
    med_counts
),
with_outcomes AS (
  -- 4. Compute LOS, mortality, and 30-day readmission flag for each admission
  SELECT
    wq.*,
    DATE_DIFF(wq.dischtime, wq.admittime, DAY) AS los_days,
    wq.hospital_expire_flag AS inpatient_mortality,
    -- 30-day readmission: exists another admission within 30 days
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS r
        WHERE
          r.subject_id = wq.subject_id
          AND r.admittime > wq.dischtime
          AND r.admittime <= TIMESTAMP_ADD(wq.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    with_quintile AS wq
)
-- 5. Aggregate results by quintile
SELECT
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(inpatient_mortality), 3) AS prop_inpatient_mortality,
  ROUND(AVG(readmit_30d), 3) AS prop_readmit_30d
FROM
  with_outcomes
GROUP BY
  quintile
ORDER BY
  quintile;