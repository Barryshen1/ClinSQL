WITH admissions_info AS (
    -- Step 1: Get admission details and calculate age at admission
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
),
t2dm_admissions AS (
    -- Step 2: Identify admissions with Type 2 Diabetes Mellitus (T2DM)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code BETWEEN '25000' AND '25093'
         -- Exclude Type 1 DM (250.x1, 250.x3 in ICD-9)
         AND NOT (SUBSTR(di.icd_code, 4, 1) = '1' OR SUBSTR(di.icd_code, 4, 1) = '3')
        )
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'E11%') -- E11.x for Type 2 DM
),
hf_admissions AS (
    -- Step 3: Identify admissions with Heart Failure (HF)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%') -- 428.xx for Heart Failure
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'I50%')  -- I50.x for Heart Failure
),
target_admissions AS (
    -- Step 4: Combine criteria to get the final target population
    SELECT
        ai.subject_id,
        ai.hadm_id,
        ai.admittime,
        ai.dischtime
    FROM
        admissions_info ai
    INNER JOIN
        t2dm_admissions t2dm ON ai.hadm_id = t2dm.hadm_id
    INNER JOIN
        hf_admissions hf ON ai.hadm_id = hf.hadm_id
    WHERE
        ai.gender = 'M'
        AND ai.age_at_admission BETWEEN 45 AND 55
),
glp1_prescriptions AS (
    -- Step 5: Identify GLP-1 agonist prescriptions for target admissions
    SELECT
        t.hadm_id,
        p.starttime,
        p.stoptime
    FROM
        target_admissions t
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON t.subject_id = p.subject_id AND t.hadm_id = p.hadm_id
    WHERE
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%lixisenatide%'
),
glp1_usage_flags AS (
    -- Step 6: Determine GLP-1 usage patterns for each target admission
    SELECT
        ta.hadm_id,
        -- Flag: started on GLP-1 within 72 hours of admission
        MAX(CASE
            WHEN gp.starttime IS NOT NULL
             AND gp.starttime BETWEEN ta.admittime AND DATETIME_ADD(ta.admittime, INTERVAL 72 HOUR)
            THEN 1
            ELSE 0
        END) AS started_glp1_within_72h,
        -- Flag: on GLP-1 in the last 48 hours of admission
        MAX(CASE
            WHEN gp.starttime IS NOT NULL
             AND ta.dischtime IS NOT NULL -- Corrected: dischtime is from the target_admissions (ta) CTE
             AND gp.starttime <= ta.dischtime -- Prescription started before or at discharge
             AND COALESCE(gp.stoptime, ta.dischtime) >= DATETIME_SUB(ta.dischtime, INTERVAL 48 HOUR) -- Drug active up to or past 48h before discharge
            THEN 1
            ELSE 0
        END) AS on_glp1_last_48h
    FROM
        target_admissions ta
    LEFT JOIN -- Use LEFT JOIN to include admissions without any GLP-1 prescriptions
        glp1_prescriptions gp ON ta.hadm_id = gp.hadm_id
    GROUP BY
        ta.hadm_id
)
-- Step 7: Calculate final percentages and net change
SELECT
    COUNT(DISTINCT guf.hadm_id) AS total_target_admissions,
    (SUM(guf.started_glp1_within_72h) * 100.0 / COUNT(DISTINCT guf.hadm_id)) AS pct_started_on_glp1_within_72h,
    (SUM(guf.on_glp1_last_48h) * 100.0 / COUNT(DISTINCT guf.hadm_id)) AS pct_on_glp1_in_last_48h,
    (SUM(guf.on_glp1_last_48h) * 100.0 / COUNT(DISTINCT guf.hadm_id)) - (SUM(guf.started_glp1_within_72h) * 100.0 / COUNT(DISTINCT guf.hadm_id)) AS net_change
FROM
    glp1_usage_flags guf;