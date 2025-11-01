SELECT
  APPROX_MEDIAN(icu.los) AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON icu.hadm_id = adm.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
WHERE
  UPPER(pat.gender) = 'M'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 68 AND 78
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pci
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
      ON pci.icd_code = dproc.icd_code
     AND pci.icd_version = dproc.icd_version
    WHERE pci.subject_id = adm.subject_id
      AND pci.hadm_id = adm.hadm_id
      AND (
        LOWER(dproc.long_title) LIKE '%percutaneous transluminal%' OR
        LOWER(dproc.long_title) LIKE '%angioplasty%' OR
        LOWER(dproc.long_title) LIKE '%stent%' OR
        LOWER(dproc.long_title) LIKE '%pci%'
      )
  );