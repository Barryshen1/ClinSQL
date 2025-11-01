WITH pneumonia_cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    -- classify pneumonia type: aspiration if any pneumonia diagnosis mentions aspiration
    CASE
      WHEN MAX(CASE WHEN LOWER(d.long_title) LIKE '%aspiration%' THEN 1 ELSE 0 END) = 1 THEN 'aspiration'
      ELSE 'community'
    END AS pneumonia_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(d.long_title) LIKE '%pneumonia%'
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.subject_id, p.anchor_age, p.anchor_year
),

comorb AS (
  -- simple comorbidity count per admission: count non-pneumonia diagnoses
  SELECT a.hadm_id, COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE LOWER(d.long_title) NOT LIKE '%pneumonia%'
  GROUP BY a.hadm_id
),

base AS (
  SELECT
    pc.hadm_id,
    pc.subject_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.anchor_age,
    pc.anchor_year,
    pc.pneumonia_type,
    TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) >= 8 THEN '8+'
    END AS LOS_cat
  FROM pneumonia_cohort pc
  WHERE TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) >= 1
),

detailed AS (
  SELECT
    b.*,
    MAX(IF(i.intime <= b.admittime + INTERVAL 1 DAY AND i.outtime >= b.admittime, 1, 0)) AS day1_in_ICU,
    COALESCE(c.comorb_count, 0) AS comorb_count
  FROM base b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.hadm_id = b.hadm_id
  LEFT JOIN comorb AS c
    ON c.hadm_id = b.hadm_id
  GROUP BY b.hadm_id, b.subject_id, b.admittime, b.dischtime, b.deathtime, b.anchor_age, b.anchor_year, b.pneumonia_type, b.los_days, b.LOS_cat, c.comorb_count
),

rates0 AS (
  -- day1_in_ICU = 0
  SELECT pneumonia_type, LOS_cat,
         COUNT(*) AS n0,
         SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS d0,
         AVG(comorb_count) AS avg_comorb0
  FROM detailed
  WHERE day1_in_ICU = 0
  GROUP BY pneumonia_type, LOS_cat
),

rates1 AS (
  -- day1_in_ICU = 1
  SELECT pneumonia_type, LOS_cat,
         COUNT(*) AS n1,
         SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS d1,
         AVG(comorb_count) AS avg_comorb1
  FROM detailed
  WHERE day1_in_ICU = 1
  GROUP BY pneumonia_type, LOS_cat
)

SELECT
  COALESCE(r0.pneumonia_type, r1.pneumonia_type) AS pneumonia_type,
  COALESCE(r0.LOS_cat, r1.LOS_cat) AS LOS_cat,
  r0.n0,
  r0.d0,
  ROUND(IFNULL(100.0 * r0.d0 / NULLIF(r0.n0, 0), NULL), 2) AS mortality_pct_noicu,
  r1.n1,
  r1.d1,
  ROUND(IFNULL(100.0 * r1.d1 / NULLIF(r1.n1, 0), NULL), 2) AS mortality_pct_day1icu,
  ROUND(IFNULL((100.0 * r1.d1 / NULLIF(r1.n1, 0)) - (100.0 * r0.d0 / NULLIF(r0.n0, 0)), NULL), 2) AS abs_diff_pct,
  SAFE_DIVIDE(
    (100.0 * r1.d1 / NULLIF(r1.n1, 0)),
    (100.0 * r0.d0 / NULLIF(r0.n0, 0))
  ) AS rel_diff,
  COALESCE(r0.avg_comorb0, 0) AS avg_comorb_noicu,
  COALESCE(r1.avg_comorb1, 0) AS avg_comorb_day1icu
FROM rates0 r0
FULL OUTER JOIN rates1 r1
  ON r0.pneumonia_type = r1.pneumonia_type
  AND r0.LOS_cat = r1.LOS_cat
ORDER BY pneumonia_type, LOS_cat;