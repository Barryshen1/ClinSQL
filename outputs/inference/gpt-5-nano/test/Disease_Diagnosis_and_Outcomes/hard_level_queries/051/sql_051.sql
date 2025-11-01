WITH pancreatitis_ads AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '577.0')
          OR (di.icd_version = 10 AND REGEXP_CONTAINS(LOWER(di.icd_code), r'^k85'))
        )
    )
),
diag_counts AS (
  SELECT a.hadm_id,
         COUNT(DISTINCT CONCAT(CAST(di.icd_version AS STRING), '||', di.icd_code)) AS diag_count
  FROM pancreatitis_ads AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  GROUP BY a.hadm_id
),
major_counts AS (
  SELECT a.hadm_id,
         SUM(
           CASE
             WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'(respiratory failure|shock|sepsis|septicemia|kidney failure|renal failure|hepatic failure|liver failure|organ failure|multi-organ failure)')
             THEN 1
             ELSE 0
           END
         ) AS major_comp_count
  FROM pancreatitis_ads AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY a.hadm_id
),
base AS (
  SELECT
    a.hadm_id,
    COALESCE(dc.diag_count, 0) AS diag_count,
    COALESCE(mc.major_comp_count, 0) AS major_comp_count,
    (COALESCE(dc.diag_count, 0) + 5 * COALESCE(mc.major_comp_count, 0)) AS risk_score,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END AS death_ind
  FROM pancreatitis_ads AS a
  LEFT JOIN diag_counts AS dc ON a.hadm_id = dc.hadm_id
  LEFT JOIN major_counts AS mc ON a.hadm_id = mc.hadm_id
),
quart_by_hadm AS (
  SELECT
    hadm_id,
    risk_score,
    los_days,
    death_ind,
    diag_count,
    major_comp_count,
    NTILE(4) OVER (ORDER BY risk_score) AS quart
  FROM base
)
SELECT
  quart_rank,
  quart_label,
  mortality_rate,
  major_comp_rate,
  median_survivor_los
FROM (
  SELECT
    q.quart AS quart_rank,
    CONCAT('Q', CAST(q.quart AS STRING)) AS quart_label,
    AVG(q.death_ind) AS mortality_rate,
    AVG(CASE WHEN q.major_comp_count > 0 THEN 1.0 ELSE 0.0 END) AS major_comp_rate,
    MEDIAN(CASE WHEN q.death_ind = 0 THEN q.los_days ELSE NULL END) AS median_survivor_los
  FROM quart_by_hadm q
  GROUP BY q.quart

  UNION ALL

  SELECT
    5 AS quart_rank,
    'Overall' AS quart_label,
    AVG(base.death_ind) AS mortality_rate,
    AVG(CASE WHEN base.major_comp_count > 0 THEN 1.0 ELSE 0.0 END) AS major_comp_rate,
    MEDIAN(CASE WHEN base.death_ind = 0 THEN base.los_days ELSE NULL END) AS median_survivor_los
  FROM base
) AS t
ORDER BY quart_rank;