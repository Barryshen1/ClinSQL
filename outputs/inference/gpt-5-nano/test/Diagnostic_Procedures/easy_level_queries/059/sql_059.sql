WITH target_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT c.icd_code) AS cardiac_distinct_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` c
    ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON c.icd_code = d.icd_code AND c.icd_version = d.icd_version
  WHERE UPPER(p.gender) LIKE 'M%'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(d.long_title) LIKE '%cardiac%'
  GROUP BY a.hadm_id
),
iqr_values AS (
  SELECT APPROX_QUANTILES(cardiac_distinct_count, 4) AS quantiles
  FROM target_counts
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM iqr_values;