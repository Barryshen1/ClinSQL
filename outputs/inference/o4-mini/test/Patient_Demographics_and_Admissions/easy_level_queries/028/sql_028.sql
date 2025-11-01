SELECT
  STDDEV_POP(i.los) AS sd_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
USING(subject_id)
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND EXISTS (
    SELECT
      1
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON
      d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
    WHERE
      d.subject_id = i.subject_id
      AND d.hadm_id = i.hadm_id
      AND LOWER(dd.long_title) LIKE '%sepsis%'
  );