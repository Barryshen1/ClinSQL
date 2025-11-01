WITH PatientLOS AS (
    -- Step 1 & 3: Filter patients by age/gender and calculate hospital LOS for each admission
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 94
        AND a.dischtime IS NOT NULL
        AND a.admittime IS NOT NULL
        AND a.dischtime > a.admittime -- Ensure valid, positive LOS
),
UGIB_Admissions AS (
    -- Step 2: Identify admissions with a primary UGIB diagnosis
    SELECT DISTINCT
        pl.subject_id,
        pl.hadm_id,
        pl.los_days
    FROM
        PatientLOS AS pl
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON pl.subject_id = di.subject_id AND pl.hadm_id = di.hadm_id
    WHERE
        di.seq_num = 1 -- Filter for primary diagnosis
        AND (
            -- ICD-9 codes for Upper GI Bleed
            (di.icd_version = 9 AND (
                di.icd_code LIKE '578%'             -- Hemorrhage of gastrointestinal tract (e.g., 5780 Hematemesis, 5781 Melena)
                OR di.icd_code = '4560'             -- Esophageal varices with bleeding
                OR di.icd_code = '53082'            -- Esophageal hemorrhage, not variceal
                OR di.icd_code = '53070'            -- Mallory-Weiss syndrome with hemorrhage
                -- Peptic/gastric/duodenal ulcers with hemorrhage (ICD-9 codes typically end in '1' for hemorrhage)
                OR (di.icd_code LIKE '531_1' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6','7','9')) -- Gastric ulcer with hemorrhage
                OR (di.icd_code LIKE '532_1' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6','7','9')) -- Duodenal ulcer with hemorrhage
                OR (di.icd_code LIKE '533_1' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6','7','9')) -- Peptic ulcer NOS with hemorrhage
                OR (di.icd_code LIKE '534_1' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6','7','9')) -- Gastrojejunal ulcer with hemorrhage
            ))
            OR
            -- ICD-10 codes for Upper GI Bleed
            (di.icd_version = 10 AND (
                di.icd_code LIKE 'K92%'             -- Gastrointestinal hemorrhage (e.g., K920 Hematemesis, K921 Melena)
                OR di.icd_code = 'I8500'            -- Esophageal varices with bleeding
                OR di.icd_code = 'K226'             -- Mallory-Weiss tear with hemorrhage
                -- Peptic/gastric/duodenal ulcers with hemorrhage (ICD-10 codes indicative of hemorrhage: X.0, X.2, X.4, X.6)
                OR (di.icd_code LIKE 'K25%' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6')) -- Gastric ulcer with hemorrhage
                OR (di.icd_code LIKE 'K26%' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6')) -- Duodenal ulcer with hemorrhage
                OR (di.icd_code LIKE 'K27%' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6')) -- Peptic ulcer NOS with hemorrhage
                OR (di.icd_code LIKE 'K28%' AND SUBSTR(di.icd_code, 4, 1) IN ('0','2','4','6')) -- Gastrojejunal ulcer with hemorrhage
            ))
        )
)
-- Step 4: Calculate the Interquartile Range (IQR) of LOS
SELECT
    PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr_los_days
FROM
    UGIB_Admissions
LIMIT 1;