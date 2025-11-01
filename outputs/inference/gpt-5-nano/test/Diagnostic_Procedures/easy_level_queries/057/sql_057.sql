WITH female_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 64 AND 74
),
patient_counts AS (
  SELECT f.subject_id,
         SUM(CASE WHEN di.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS catheter_count
  FROM female_cohort f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = f.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pi.subject_id = f.subject_id AND pi.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
    ON pi.icd_code = di.icd_code
   AND pi.icd_version = di.icd_version
   AND LOWER(di.long_title) LIKE '%cardiac catheterization%'
  GROUP BY f.subject_id
)
SELECT MIN(catheter_count) AS min_number_of_diagnostic_card_icath_per_patient
FROM patient_counts;