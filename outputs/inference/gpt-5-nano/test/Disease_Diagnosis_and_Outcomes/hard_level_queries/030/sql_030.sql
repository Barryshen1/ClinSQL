WITH base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    -- diag_count: number of distinct ICD codes for this admission
    (
      SELECT COUNT(DISTINCT di.icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
    ) AS diag_count,
    -- major_comp: 1 if there exists a Major DRG severity for this admission, else 0
    COALESCE(
      (
        SELECT MAX(CASE WHEN gc.drg_severity = 'Major' THEN 1 ELSE 0 END)
        FROM `physionet-data.mimiciv_3_1_hosp.drgcodes` gc
        WHERE gc.subject_id = a.subject_id
          AND gc.hadm_id = a.hadm_id
      ),
      0
    ) AS major_comp
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 64 AND 74
    -- UGIB: ensure this admission has an upper GI bleeding diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dd.icd_code = di.icd_code
       AND dd.icd_version = di.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%upper gastrointestinal hemorrhage%'
          OR LOWER(dd.long_title) LIKE '%upper gastrointestinal bleed%'
          OR LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
          OR LOWER(dd.long_title) LIKE '%gastric hemorrhage%'
          OR di.icd_code IN ('578.0','578.1','578.9') -- common UGIB codes (ICD-9)
        )
    )
),
scored AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    diag_count,
    major_comp,
    (diag_count + 20 * major_comp) AS score,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1 AS los_days,
    CASE
      WHEN deathtime IS NOT NULL
           AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS mort30
  FROM base_admissions
)
SELECT
  quintile,
  COUNT(*) AS n,
  AVG(score) AS mean_score,
  100.0 * SUM(mort30) / COUNT(*) AS mortality_30_day_percent,
  100.0 * SUM(major_comp) / COUNT(*) AS major_complication_percent,
  APPROX_MEDIAN(los_days) FILTER (WHERE mort30 = 0) AS median_los_survivors
FROM (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY score) AS quintile
  FROM scored
) t
GROUP BY quintile
ORDER BY quintile;