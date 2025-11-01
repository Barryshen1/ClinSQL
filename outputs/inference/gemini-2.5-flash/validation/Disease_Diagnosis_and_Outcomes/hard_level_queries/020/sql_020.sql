WITH AdmissionsFiltered AS (
    -- Step 1: Filter admissions for the target cohort (male, age 46-56, AMI diagnosis)
    SELECT
        pa.subject_id,
        ad.hadm_id,
        pa.anchor_age,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 46 AND 56
        AND EXISTS ( -- Check for Acute Myocardial Infarction (AMI) diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.icd_version = 10
                AND SUBSTR(di.icd_code, 1, 3) = 'I21' -- ICD-10 for Acute Myocardial Infarction
        )
),
MajorComplications AS (
    -- Step 2: Identify and count distinct major complications for each admission in the filtered cohort
    SELECT
        di.hadm_id,
        COUNT(DISTINCT
            CASE
                WHEN SUBSTR(di.icd_code, 1, 3) = 'I50' THEN 'Heart_Failure' -- ICD-10 for Heart Failure
                WHEN SUBSTR(di.icd_code, 1, 3) = 'N17' THEN 'AKI'           -- ICD-10 for Acute Kidney Injury
                WHEN SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64') THEN 'Stroke' -- ICD-10 for various Stroke types
                WHEN SUBSTR(di.icd_code, 1, 3) IN ('A40', 'A41') THEN 'Sepsis' -- ICD-10 for Sepsis
                WHEN SUBSTR(di.icd_code, 1, 3) = 'J96' THEN 'Respiratory_Failure' -- ICD-10 for Respiratory failure
                ELSE NULL
            END
        ) AS major_complications_count
    FROM
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE
        di.icd_version = 10
        AND di.hadm_id IN (SELECT hadm_id FROM AdmissionsFiltered)
        AND ( -- Filter condition to only consider relevant major complication codes
            SUBSTR(di.icd_code, 1, 3) = 'I50' OR
            SUBSTR(di.icd_code, 1, 3) = 'N17' OR
            SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64') OR
            SUBSTR(di.icd_code, 1, 3) IN ('A40', 'A41') OR
            SUBSTR(di.icd_code, 1, 3) = 'J96'
        )
    GROUP BY di.hadm_id
),
CohortWithScores AS (
    -- Step 3: Combine filtered admissions with major complications and calculate composite risk score and LOS
    SELECT
        a.hadm_id,
        a.anchor_age,
        a.hospital_expire_flag,
        COALESCE(mc.major_complications_count, 0) AS major_complications_count,
        -- Flag to indicate if any major complication occurred (for major_complication_percent)
        CASE WHEN COALESCE(mc.major_complications_count, 0) > 0 THEN 1 ELSE 0 END AS has_major_complication_flag,
        -- Composite risk score: age + number of distinct major complication types
        a.anchor_age + COALESCE(mc.major_complications_count, 0) AS composite_risk_score,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM
        AdmissionsFiltered a
    LEFT JOIN
        MajorComplications mc
        ON a.hadm_id = mc.hadm_id
),
CohortWithQuintiles AS (
    -- Step 4: Assign risk quintiles based on the composite risk score
    SELECT
        *,
        NTILE(5) OVER (ORDER BY composite_risk_score ASC) AS risk_quintile
    FROM
        CohortWithScores
),
MedianLOS AS (
    -- Calculate median Length of Stay specifically for survivors within each quintile
    SELECT
        risk_quintile,
        -- Corrected PERCENTILE_CONT syntax for BigQuery aggregate function
        PERCENTILE_CONT(los_days, 0.5) AS median_survivor_los_days
    FROM
        CohortWithQuintiles
    WHERE
        hospital_expire_flag = 0 -- Only include survivors for this calculation
    GROUP BY
        risk_quintile
)
-- Step 5: Final aggregation to calculate and report all requested metrics per quintile
SELECT
    t1.risk_quintile,
    MIN(t1.composite_risk_score) AS min_composite_score_in_quintile,
    MAX(t1.composite_risk_score) AS max_composite_score_in_quintile,
    COUNT(t1.hadm_id) AS total_admissions,
    SAFE_DIVIDE(SUM(CASE WHEN t1.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(t1.hadm_id)) * 100 AS in_hospital_mortality_percent,
    SAFE_DIVIDE(SUM(t1.has_major_complication_flag), COUNT(t1.hadm_id)) * 100 AS major_complication_percent,
    ml.median_survivor_los_days
FROM
    CohortWithQuintiles t1
LEFT JOIN
    MedianLOS ml
    ON t1.risk_quintile = ml.risk_quintile
GROUP BY
    t1.risk_quintile
    -- Removed ml.median_survivor_los_days from GROUP BY as it is functionally dependent on t1.risk_quintile
ORDER BY
    t1.risk_quintile;