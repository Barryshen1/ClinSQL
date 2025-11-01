WITH cohort AS (
  -- Eligible patients: female, age 41-51
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),
cabg_events AS (
  -- CABG-related procedure events, identified via ICD codes with descriptive long_title
  SELECT DISTINCT
         p.subject_id,
         p.hadm_id,
         p.chartdate AS event_chartdate,
         p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cabg%'
     OR LOWER(d.long_title) LIKE '%coronary bypass graft%'
)
SELECT STDDEV_SAMP(n_cabg) AS cabg_stddev
FROM (
  SELECT c.subject_id,
         COUNT(DISTINCT CAST(g.hadm_id AS STRING) || '|' || CAST(g.event_chartdate AS STRING) || '|' || CAST(g.icd_code AS STRING)) AS n_cabg
  FROM cohort AS c
  LEFT JOIN cabg_events AS g
    ON g.subject_id = c.subject_id
  GROUP BY c.subject_id
) AS t;