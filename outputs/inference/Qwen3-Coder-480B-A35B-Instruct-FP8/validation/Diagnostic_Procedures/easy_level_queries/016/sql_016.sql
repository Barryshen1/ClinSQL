SELECT
  APPROX_QUANTILES(distinct_procedures_per_hadm, 100)[OFFSET(75)] AS percentile_75
FROM (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedures_per_hadm
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.hadm_id = a.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON a.subject_id = pat.subject_id
  WHERE
    (LOWER(d.long_title) LIKE '%ecg%' OR LOWER(d.long_title) LIKE '%telemetry%')
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
  GROUP BY
    p.hadm_id
);