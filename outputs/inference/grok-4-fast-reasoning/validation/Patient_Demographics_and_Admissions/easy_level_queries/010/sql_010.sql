SELECT
  APPROX_QUANTILES(i.los, 100)[OFFSET(25)] AS p25_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  i.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 48 AND 58
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
      d.hadm_id = i.hadm_id
      AND (d.icd_code LIKE '584%' OR d.icd_code LIKE 'N17%')
  );