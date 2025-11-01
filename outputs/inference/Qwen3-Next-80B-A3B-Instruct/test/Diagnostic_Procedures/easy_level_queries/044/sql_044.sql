WITH filtered_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),
mcs_procedures_hosp AS (
  SELECT DISTINCT p.subject_id,
         CASE 
           WHEN LOWER(dip.long_title) LIKE '%iabp%' THEN 'IABP'
           WHEN LOWER(dip.long_title) LIKE '%ecmo%' THEN 'ECMO'
           WHEN LOWER(dip.long_title) LIKE '%lvad%' THEN 'LVAD'
           WHEN LOWER(dip.long_title) LIKE '%rvad%' THEN 'RVAD'
           WHEN LOWER(dip.long_title) LIKE '%bivad%' THEN 'BiVAD'
           WHEN LOWER(dip.long_title) LIKE '%mechanical circulatory support%' THEN 'MCS'
           WHEN LOWER(dip.long_title) LIKE '%ventricular assist device%' THEN 'VAD'
           ELSE NULL
         END AS mcs_type
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON p.icd_code = dip.icd_code AND p.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%iabp%'
     OR LOWER(dip.long_title) LIKE '%ecmo%'
     OR LOWER(dip.long_title) LIKE '%lvad%'
     OR LOWER(dip.long_title) LIKE '%rvad%'
     OR LOWER(dip.long_title) LIKE '%bivad%'
     OR LOWER(dip.long_title) LIKE '%mechanical circulatory support%'
     OR LOWER(dip.long_title) LIKE '%ventricular assist device%'
),
mcs_procedures_icu AS (
  SELECT DISTINCT p.subject_id,
         CASE 
           WHEN LOWER(di.label) LIKE '%iabp%' THEN 'IABP'
           WHEN LOWER(di.label) LIKE '%ecmo%' THEN 'ECMO'
           WHEN LOWER(di.label) LIKE '%lvad%' THEN 'LVAD'
           WHEN LOWER(di.label) LIKE '%rvad%' THEN 'RVAD'
           WHEN LOWER(di.label) LIKE '%bivad%' THEN 'BiVAD'
           WHEN LOWER(di.label) LIKE '%mechanical circulatory support%' THEN 'MCS'
           WHEN LOWER(di.label) LIKE '%ventricular assist device%' THEN 'VAD'
           ELSE NULL
         END AS mcs_type
  FROM physionet-data.mimiciv_3_1_icu.procedureevents p
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON p.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%iabp%'
     OR LOWER(di.label) LIKE '%ecmo%'
     OR LOWER(di.label) LIKE '%lvad%'
     OR LOWER(di.label) LIKE '%rvad%'
     OR LOWER(di.label) LIKE '%bivad%'
     OR LOWER(di.label) LIKE '%mechanical circulatory support%'
     OR LOWER(di.label) LIKE '%ventricular assist device%'
),
all_mcs AS (
  SELECT subject_id, mcs_type
  FROM mcs_procedures_hosp
  WHERE mcs_type IS NOT NULL
  UNION ALL
  SELECT subject_id, mcs_type
  FROM mcs_procedures_icu
  WHERE mcs_type IS NOT NULL
),
per_patient_counts AS (
  SELECT fp.subject_id, COUNT(DISTINCT am.mcs_type) AS num_distinct_mcs_types
  FROM filtered_patients fp
  LEFT JOIN all_mcs am ON fp.subject_id = am.subject_id
  GROUP BY fp.subject_id
)
SELECT STDDEV_POP(num_distinct_mcs_types) AS std_dev_distinct_mcs_per_patient
FROM per_patient_counts;