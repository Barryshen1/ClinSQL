SELECT
  p.subject_id,
  icu.hadm_id,
  MAX(icu.los) AS max_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON p.subject_id = pr.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
  ON pr.icd_code = dpr.icd_code
  AND pr.icd_version = dpr.icd_version
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON pr.subject_id = icu.subject_id
  AND pr.hadm_id = icu.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND (
    UPPER(dpr.long_title) LIKE '%PERCUTANEOUS CORONARY%'
    OR UPPER(dpr.long_title) LIKE '%PCI%'
  )
GROUP BY
  p.subject_id,
  icu.hadm_id
ORDER BY
  p.subject_id,
  icu.hadm_id;