WITH cohort AS (
  -- 1. Identify female inpatients aged 71–81 with acute pancreatitis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON dx.icd_code = dd.icd_code
      AND dx.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),
med_complexity AS (
  -- 2. Compute the medication complexity score for each admission over the first 72 hours
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pres.drug) AS complexity_score
  FROM
    cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
      ON c.hadm_id = pres.hadm_id
      AND pres.starttime >= c.admittime
      AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id
),
adm_info AS (
  -- 3. Compute LOS, mortality, and 30-day readmission flag
  SELECT
    c.subject_id,
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    c.hospital_expire_flag AS mortality_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = c.subject_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    cohort AS c
),
scored AS (
  -- 4. Combine complexity with admission info and assign tertiles
  SELECT
    m.subject_id,
    m.hadm_id,
    m.complexity_score,
    ai.los,
    ai.mortality_flag,
    ai.readmit_30d,
    NTILE(3) OVER (ORDER BY m.complexity_score) AS complexity_tertile
  FROM
    med_complexity AS m
    JOIN adm_info AS ai
      ON m.hadm_id = ai.hadm_id
)
-- 5. Aggregate results by tertile
SELECT
  complexity_tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS avg_los_days,
  ROUND(AVG(mortality_flag) * 100, 1) AS pct_inhospital_mortality,
  ROUND(AVG(readmit_30d) * 100, 1) AS pct_30d_readmission
FROM
  scored
GROUP BY
  complexity_tertile
ORDER BY
  complexity_tertile;