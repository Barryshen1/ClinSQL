WITH female_patients_40_50 AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
mcs_procedures AS (
  SELECT DISTINCT pi.subject_id, pi.icd_code
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%mechanical circulatory support%'
     OR LOWER(dip.long_title) LIKE '%ecmo%'
     OR LOWER(dip.long_title) LIKE '%iabp%'
     OR LOWER(dip.long_title) LIKE '%lvad%'
     OR LOWER(dip.long_title) LIKE '%rvad%'
     OR LOWER(dip.long_title) LIKE '%bivad%'
     OR LOWER(dip.long_title) LIKE '%total artificial heart%'
     OR LOWER(dip.long_title) LIKE '%artificial heart%'
),
patient_mcs_counts AS (
  SELECT fp.subject_id,
         COUNT(DISTINCT mp.icd_code) AS num_distinct_mcs_procedures
  FROM female_patients_40_50 fp
  INNER JOIN mcs_procedures mp ON fp.subject_id = mp.subject_id
  GROUP BY fp.subject_id
)
SELECT MIN(num_distinct_mcs_procedures) AS minimum_distinct_mcs_procedures_per_patient
FROM patient_mcs_counts;