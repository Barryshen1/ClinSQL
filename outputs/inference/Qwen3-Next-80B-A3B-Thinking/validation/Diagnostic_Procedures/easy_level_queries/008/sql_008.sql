WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),

echocardiography_procedures AS (
  SELECT pi.subject_id, pi.icd_code AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%echocardiography%'

  UNION ALL

  SELECT h.subject_id, h.hcpcs_cd AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%echocardiogram%'
)

SELECT APPROX_QUANTILES(count_procedures, 100)[OFFSET(25)] AS twenty_fifth_percentile
FROM (
  SELECT tp.subject_id, COUNT(DISTINCT ep.procedure_code) AS count_procedures
  FROM target_patients tp
  LEFT JOIN echocardiography_procedures ep
    ON tp.subject_id = ep.subject_id
  GROUP BY tp.subject_id
) counts;