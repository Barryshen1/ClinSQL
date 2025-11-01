WITH sepsis_admissions AS (
     SELECT 
       di.hadm_id,
       a.subject_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON di.hadm_id = a.hadm_id
     WHERE 
        (di.icd_version = 9 AND (di.icd_code LIKE '038%' OR di.icd_code IN ('99591','99592','78552')))
        OR (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R652%'))
     GROUP BY di.hadm_id, a.subject_id
   ),
   male_sepsis_admissions AS (
     SELECT sa.hadm_id
     FROM sepsis_admissions sa
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON sa.subject_id = p.subject_id
     WHERE p.gender = 'M'
   ),
   discharge_dates AS (
     SELECT 
       msa.hadm_id,
       DATE(a.dischtime) AS disch_date
     FROM male_sepsis_admissions msa
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON msa.hadm_id = a.hadm_id
     WHERE a.dischtime IS NOT NULL
   ),
   lactate_measurements AS (
     SELECT 
       dd.hadm_id,
       le.charttime,
       le.valuenum
     FROM discharge_dates dd
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON dd.hadm_id = le.hadm_id
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
     WHERE 
        dli.label = 'Lactate'
        AND DATE(le.charttime) = dd.disch_date
        AND le.valuenum IS NOT NULL
   ),
   last_lactate AS (
     SELECT 
       hadm_id,
       valuenum,
       ROW_NUMBER() OVER (
         PARTITION BY hadm_id 
         ORDER BY charttime DESC
       ) AS rn
     FROM lactate_measurements
   )
   SELECT 
     APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] 
     - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr
   FROM last_lactate
   WHERE rn = 1;