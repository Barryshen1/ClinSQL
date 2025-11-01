WITH qualifying_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 82 AND 92
),
qualifying_hadms AS (
  SELECT DISTINCT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN qualifying_patients qp 
    ON a.subject_id = qp.subject_id
),
cardiac_counts AS (
  SELECT 
    pi.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS num_distinct
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  JOIN qualifying_hadms qh 
    ON pi.hadm_id = qh.hadm_id
  WHERE (
    LOWER(dip.long_title) LIKE '%heart%'
    OR LOWER(dip.long_title) LIKE '%cardiac%'
    OR LOWER(dip.long_title) LIKE '%coronary%'
    OR LOWER(dip.long_title) LIKE '%aort%'
    OR LOWER(dip.long_title) LIKE '%valv%'
    OR LOWER(dip.long_title) LIKE '%bypass%'
    OR LOWER(dip.long_title) LIKE '%pericard%'
    OR LOWER(dip.long_title) LIKE '%myocard%'
  )
  GROUP BY pi.hadm_id
)
SELECT 
  PERCENTILE_CONT(num_distinct, 0.25) AS p25_num_distinct_cardiac_procs
FROM (
  SELECT 
    COALESCE(cc.num_distinct, 0) AS num_distinct
  FROM qualifying_hadms qh
  LEFT JOIN cardiac_counts cc 
    ON qh.hadm_id = cc.hadm_id
);