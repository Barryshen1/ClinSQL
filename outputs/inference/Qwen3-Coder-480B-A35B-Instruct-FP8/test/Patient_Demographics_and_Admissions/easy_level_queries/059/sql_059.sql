SELECT
  icu.hadm_id,
  MAX(icu.los) AS max_icu_los
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  ON adm.hadm_id = proc.hadm_id
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 59 AND 69
  AND proc.icd_code = '02560ZZ'
  AND proc.icd_version = 10
GROUP BY
  icu.hadm_id
ORDER BY
  max_icu_los DESC;