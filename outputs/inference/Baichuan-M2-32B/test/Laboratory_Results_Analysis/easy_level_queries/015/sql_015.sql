WITH pneumonia_codes AS (
     SELECT DISTINCT icd_code, icd_version
     FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
     WHERE LOWER(long_title) LIKE '%pneumonia%'
   ),
   creatinine_itemids AS (
     SELECT DISTINCT itemid
     FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
     WHERE category = 'Chemistry' 
       AND LOWER(label) LIKE '%creatinine%'
       AND LOWER(label) LIKE '%serum%'
   ),
   female_patients AS (
     SELECT subject_id
     FROM `physionet-data.mimiciv_3_1_hosp.patients`
     WHERE gender = 'F'
   ),
   pneumonia_admissions AS (
     SELECT DISTINCT d.hadm_id, d.subject_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     JOIN pneumonia_codes p ON d.icd_code = p.icd_code AND d.icd_version = p.icd_version
     JOIN female_patients f ON d.subject_id = f.subject_id
   ),
   admission_times AS (
     SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
     JOIN pneumonia_admissions p ON a.hadm_id = p.hadm_id
     WHERE a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
   ),
   creatinine_labs AS (
     SELECT l.hadm_id, l.subject_id, l.charttime, l.valuenum, a.admittime
     FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
     JOIN creatinine_itemids c ON l.itemid = c.itemid
     JOIN admission_times a ON l.hadm_id = a.hadm_id
     WHERE l.charttime BETWEEN a.admittime AND a.dischtime
       AND l.valuenum IS NOT NULL
       AND l.valuenum > 0
   ),
   windowed_creatinine AS (
     SELECT 
       c.subject_id, 
       c.hadm_id,
       c.charttime,
       c.valuenum,
       TIMESTAMP_DIFF(c.charttime, c.admittime, HOUR) AS hours_since_admission,
       FLOOR(TIMESTAMP_DIFF(c.charttime, c.admittime, HOUR) / 24) AS window_index
     FROM creatinine_labs c
   ),
   avg_per_window AS (
     SELECT 
       subject_id, 
       hadm_id,
       window_index,
       AVG(valuenum) AS avg_creatinine
     FROM windowed_creatinine
     GROUP BY subject_id, hadm_id, window_index
   )
   SELECT MIN(avg_creatinine) AS min_24h_avg_creatinine
   FROM avg_per_window;