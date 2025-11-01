WITH procedures_per_admission AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS num_valve_procedures
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON p.icd_code = dip.icd_code AND p.icd_version = dip.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 52 AND 62
    AND LOWER(dip.long_title) LIKE '%valve%'
    AND (LOWER(dip.long_title) LIKE '%repair%'
         OR LOWER(dip.long_title) LIKE '%replacement%'
         OR LOWER(dip.long_title) LIKE '%valvuloplasty%'
         OR LOWER(dip.long_title) LIKE '%valvotomy%')
  GROUP BY p.hadm_id
)
SELECT
  APPROX_QUANTILES(num_valve_procedures, 3)[OFFSET(0)] AS q1,
  APPROX_QUANTILES(num_valve_procedures, 3)[OFFSET(2)] AS q3
FROM procedures_per_admission;