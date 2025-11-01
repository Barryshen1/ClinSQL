WITH hf_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, p.gender, p.anchor_age, adm.admittime, adm.dischtime, adm.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON adm.subject_id = d.subject_id 
    AND adm.hadm_id = d.hadm_id
  WHERE p.anchor_age = 74
    AND p.gender = 'F'
    AND (
         (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
         OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
),
los_filtered AS (
  SELECT
    hfp.subject_id,
    hfp.hadm_id,
    hfp.gender,
    hfp.anchor_age,
    hfp.admission_type,
    DATE_DIFF(DATE(hfp.dischtime), DATE(hfp.admittime), DAY) AS los_days
  FROM hf_patients hfp
),
los_grouped AS (
  SELECT *,
         CASE
           WHEN los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
           WHEN los_days BETWEEN 5 AND 7 THEN 'LOS_5_7'
           ELSE NULL
         END AS los_group
  FROM los_filtered
  WHERE los_days BETWEEN 1 AND 7
),
procedures_noninv AS (
  SELECT pr.subject_id, pr.hadm_id, COUNT(*) AS num_noninv
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE UPPER(dp.long_title) LIKE '%X-RAY%'
     OR UPPER(dp.long_title) LIKE '%CT%'
     OR UPPER(dp.long_title) LIKE '%MRI%'
     OR UPPER(dp.long_title) LIKE '%ULTRASOUND%'
     OR UPPER(dp.long_title) LIKE '%ECG%'
     OR UPPER(dp.long_title) LIKE '%ELECTROCARDIOGRAM%'
     OR UPPER(dp.long_title) LIKE '%EEG%'
     OR UPPER(dp.long_title) LIKE '%ELECTROENCEPHALOGRAM%'
     OR UPPER(dp.long_title) LIKE '%PULMONARY FUNCTION%'
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT
  lg.los_group,
  CASE
    WHEN UPPER(lg.admission_type) LIKE '%URGENT%' OR UPPER(lg.admission_type) LIKE '%EMER%' THEN 'ED/Urgent'
    WHEN UPPER(lg.admission_type) LIKE '%ELECTIVE%' THEN 'Elective'
    ELSE 'Other'
  END AS admission_category,
  COUNT(DISTINCT lg.hadm_id) AS num_admissions,
  AVG(IFNULL(pn.num_noninv, 0)) AS mean_noninv_procs_per_adm
FROM los_grouped lg
LEFT JOIN procedures_noninv pn
  ON lg.subject_id = pn.subject_id
 AND lg.hadm_id = pn.hadm_id
WHERE lg.los_group IS NOT NULL
GROUP BY lg.los_group, admission_category
ORDER BY lg.los_group, admission_category;