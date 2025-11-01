WITH pci_encounters AS (
  SELECT DISTINCT pc.subject_id, pc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON dp.icd_code = pc.icd_code
   AND dp.icd_version = pc.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = pc.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      LOWER(dp.long_title) LIKE '%angioplasty%'
      OR LOWER(dp.long_title) LIKE '%stent%'
      OR LOWER(dp.long_title) LIKE '%percutaneous%'
      OR LOWER(dp.long_title) LIKE '%pci%'
    )
)
SELECT
  pi.hadm_id,
  MAX(i.los) AS max_icu_los_hours
FROM pci_encounters AS pi
JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
  ON i.subject_id = pi.subject_id
 AND i.hadm_id = pi.hadm_id
GROUP BY pi.hadm_id
ORDER BY max_icu_los_hours DESC;