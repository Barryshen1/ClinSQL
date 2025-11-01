WITH filtered_los AS (
  SELECT DISTINCT i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
          UPPER(p.gender) = 'F'
          OR p.gender = 'Female'
          OR p.gender = 'FEMALE'
        )
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
          UPER(dd.long_title) LIKE '%SEPSIS%'
          OR UPER(dd.long_title) LIKE '%SEPTIC%'
          OR UPER(dd.long_title) LIKE '%SEPTICEMIA%'
        )
    AND i.los IS NOT NULL
)
SELECT MEDIAN(los) AS median_icu_los_days
FROM filtered_los;