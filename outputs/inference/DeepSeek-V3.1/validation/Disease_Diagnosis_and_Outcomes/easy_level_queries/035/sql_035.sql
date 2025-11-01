WITH gi_bleed_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE 
        diag.seq_num = 1  -- primary diagnosis
        AND p.gender = 'M'
        AND p.anchor_age = 70
        AND (
            -- ICD-10 codes for upper GI bleeding
            (diag.icd_version = 10 AND (
                d.icd_code LIKE 'K25%' OR  -- gastric ulcer with bleeding
                d.icd_code LIKE 'K26%' OR  -- duodenal ulcer with bleeding
                d.icd_code LIKE 'K27%' OR  -- peptic ulcer with bleeding
                d.icd_code LIKE 'K28%' OR  -- gastrojejunal ulcer with bleeding
                d.icd_code = 'K92.0' OR    -- hematemesis
                d.icd_code = 'K92.1' OR    -- melena
                d.icd_code = 'K92.2'       -- gastrointestinal hemorrhage, unspecified
            )) OR
            -- ICD-9 codes for upper GI bleeding
            (diag.icd_version = 9 AND (
                d.icd_code LIKE '531%' OR   -- gastric ulcer with bleeding
                d.icd_code LIKE '532%' OR   -- duodenal ulcer with bleeding
                d.icd_code LIKE '533%' OR   -- peptic ulcer with bleeding
                d.icd_code LIKE '534%' OR   -- gastrojejunal ulcer with bleeding
                d.icd_code = '578.0' OR     -- hematemesis
                d.icd_code = '578.1' OR     -- melena
                d.icd_code = '578.9'        -- gastrointestinal hemorrhage, unspecified
            ))
        )
        AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM gi_bleed_admissions;