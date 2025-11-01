WITH eligible_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) IN ('female', 'f')
    AND p.anchor_age BETWEEN 86 AND 96
),

-- 2) For each hospitalization, count distinct MCS procedures
--    by mapping icd codes to long titles and filtering for MCS-related terms
mcs_counts AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT CASE
      WHEN d.long_title IS NOT NULL
           AND (
                LOWER(d.long_title) LIKE '%ecmo%'
                OR LOWER(d.long_title) LIKE '%intra-aortic balloon%'
                OR LOWER(d.long_title) LIKE '%balloon pump%'
                OR LOWER(d.long_title) LIKE '%ventricular assist%'
                OR LOWER(d.long_title) LIKE '%left ventricular assist%'
                OR LOWER(d.long_title) LIKE '%total artificial heart%'
                OR LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%'
                OR LOWER(d.long_title) LIKE '%venoarterial%'
                OR LOWER(d.long_title) LIKE '%va-ecmo%'
              )
      THEN p.icd_code
      ELSE NULL
    END) AS mcs_count
  FROM eligible_hadm e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON e.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  GROUP BY e.hadm_id
)

-- 3) Compute the IQR (Q1 and Q3) of the per-hospitalization MCS counts
SELECT
  PERCENTILE_CONT(mcs_count, 0.25) OVER () AS q1,
  PERCENTILE_CONT(mcs_count, 0.75) OVER () AS q3,
  (PERCENTILE_CONT(mcs_count, 0.75) OVER () - PERCENTILE_CONT(mcs_count, 0.25) OVER ()) AS iqr
FROM mcs_counts
LIMIT 1;