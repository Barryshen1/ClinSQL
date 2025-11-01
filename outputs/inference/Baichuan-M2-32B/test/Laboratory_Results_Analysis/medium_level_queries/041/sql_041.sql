WITH patient_age AS (
     SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        p.anchor_year,
        p.anchor_age,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
     FROM `physionet-data.mimiciv_3_1_hosp.patients` p
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
     WHERE p.gender = 'M'
   ),
   acs_admissions AS (
     SELECT DISTINCT
        hadm_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.icd_version = 10
        AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I24.0%')
   ),
   troponin_labs AS (
     SELECT 
        l.subject_id,
        l.hadm_id,
        l.labevent_id,
        l.charttime,
        l.valuenum,
        l.valueuom,
        l.ref_range_upper,
        d.label
     FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
     WHERE (d.label LIKE '%hs-Troponin T%')
        AND l.valuenum IS NOT NULL
   ),
   first_troponin_per_admission AS (
     SELECT 
        subject_id,
        hadm_id,
        charttime,
        valuenum,
        valueuom,
        ref_range_upper
     FROM (
        SELECT 
           t.*,
           ROW_NUMBER() OVER (PARTITION BY t.subject_id, t.hadm_id ORDER BY t.charttime, t.labevent_id) AS rn
        FROM troponin_labs t
     ) 
     WHERE rn = 1
   ),
   troponin_values AS (
     SELECT 
        subject_id,
        hadm_id,
        valuenum,
        valueuom,
        ref_range_upper,
        -- Convert value to ng/mL
        CASE 
            WHEN valueuom = 'ng/mL' THEN valuenum
            WHEN valueuom = 'ng/L' THEN valuenum / 1000.0
            ELSE NULL 
        END AS value_ngml,
        -- Convert ULN to ng/mL if available, else use fixed 0.014 ng/mL
        CASE 
            WHEN ref_range_upper IS NOT NULL THEN 
                CASE 
                    WHEN valueuom = 'ng/mL' THEN ref_range_upper
                    WHEN valueuom = 'ng/L' THEN ref_range_upper / 1000.0
                    ELSE NULL 
                END
            ELSE 0.014 
        END AS uln_ngml
     FROM first_troponin_per_admission
   ),
   qualifying_admissions AS (
     SELECT 
        pa.subject_id,
        pa.hadm_id,
        tv.value_ngml
     FROM patient_age pa
     INNER JOIN acs_admissions a 
        ON pa.hadm_id = a.hadm_id
     INNER JOIN troponin_values tv 
        ON pa.hadm_id = tv.hadm_id
     WHERE pa.age_at_admission BETWEEN 43 AND 53
        AND tv.value_ngml > tv.uln_ngml
   )
   SELECT 
      APPROX_QUANTILES(value_ngml, 1000)[OFFSET(500)] AS median,
      APPROX_QUANTILES(value_ngml, 1000)[OFFSET(750)] - APPROX_QUANTILES(value_ngml, 1000)[OFFSET(250)] AS iqr
   FROM qualifying_admissions;