WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- 90-day mortality flag
    CASE
      WHEN a.deathtime IS NOT NULL 
           AND DATE_DIFF(a.deathtime, a.admittime, DAY) <= 90 
      THEN 1 ELSE 0
    END AS died90,
    -- flag if any major complication code appears on this admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
        WHERE di2.hadm_id = a.hadm_id
          AND di2.icd_code IN ('K65.0','K72.0','K83.0')
      ) THEN 1 ELSE 0
    END AS complication_flag,
    -- composite risk score = count of complication codes on the admission
    (
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di3
      WHERE di3.hadm_id = a.hadm_id
        AND di3.icd_code IN ('K65.0','K72.0','K83.0')
    ) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- primary diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(dd.long_title) LIKE '%lower gastrointestinal bleeding%'
),
scored AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM base
)
SELECT
  quintile,
  COUNT(*) AS N,
  ROUND(AVG(died90), 3) AS mortality_90d_rate,
  ROUND(AVG(complication_flag), 3) AS major_complication_rate,
  -- median LOS among 90-day survivors
  APPROX_QUANTILES(IF(died90 = 0, los, NULL), 2)[OFFSET(1)] AS median_los_survivors
FROM scored
GROUP BY quintile
ORDER BY quintile;