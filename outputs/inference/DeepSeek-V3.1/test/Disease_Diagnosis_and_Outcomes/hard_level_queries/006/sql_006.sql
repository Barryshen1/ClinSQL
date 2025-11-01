WITH gi_bleed_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.deathtime,
        adm.hospital_expire_flag,
        pat.dod,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 70 AND 80
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE adm.hadm_id = diag.hadm_id
                AND (diag.icd_code LIKE 'K62.5%'    -- Rectal hemorrhage
                    OR diag.icd_code LIKE 'K55.2%'  -- Angiodysplasia of colon with hemorrhage
                    OR diag.icd_code LIKE 'K57.4%'  -- Diverticular disease with hemorrhage
                    OR diag.icd_code LIKE 'K92.1%'  -- Melena
                    OR diag.icd_code LIKE 'K92.2%'  -- Gastrointestinal hemorrhage, unspecified
                )
        )
),

complications AS (
    SELECT 
        ga.hadm_id,
        MAX(CASE WHEN diag.icd_code LIKE 'R57%' THEN 1 ELSE 0 END) AS shock,
        MAX(CASE WHEN diag.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki,
        MAX(CASE WHEN proc.icd_code LIKE '30233N0%' 
                  OR proc.icd_code LIKE '30243N0%' 
                  OR proc.icd_code LIKE '30253N0%' THEN 1 ELSE 0 END) AS transfusion
    FROM gi_bleed_admissions ga
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ga.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON ga.hadm_id = proc.hadm_id
    GROUP BY ga.hadm_id
),

risk_scores AS (
    SELECT 
        ga.*,
        COALESCE(c.shock, 0) + COALESCE(c.aki, 0) + COALESCE(c.transfusion, 0) AS risk_score
    FROM gi_bleed_admissions ga
    LEFT JOIN complications c
        ON ga.hadm_id = c.hadm_id
),

quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY risk_score) AS quintile
    FROM risk_scores
),

outcomes AS (
    SELECT 
        quintile,
        COUNT(*) AS n,
        -- 90-day mortality: death within 90 days of admission
        SUM(
            CASE WHEN 
                (deathtime IS NOT NULL AND DATE_DIFF(DATE(deathtime), DATE(admittime), DAY) <= 90)
                OR (dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90)
                THEN 1 ELSE 0 
            END
        ) AS mortality_90d,
        -- Major complication rate (at least one of shock, AKI, transfusion)
        SUM(
            CASE WHEN risk_score > 0 THEN 1 ELSE 0 END
        ) AS major_complication,
        -- Median LOS for 90-day survivors
        APPROX_QUANTILE(
            CASE WHEN 
                (deathtime IS NULL OR DATE_DIFF(DATE(deathtime), DATE(admittime), DAY) > 90)
                AND (dod IS NULL OR DATE_DIFF(DATE(dod), DATE(admittime), DAY) > 90)
                THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) 
                ELSE NULL 
            END,
            0.5
        ) AS median_los_survivors
    FROM quintiles
    GROUP BY quintile
)

SELECT 
    quintile,
    n,
    mortality_90d,
    ROUND(mortality_90d * 100.0 / n, 2) AS mortality_90d_rate,
    major_complication,
    ROUND(major_complication * 100.0 / n, 2) AS major_complication_rate,
    median_los_survivors
FROM outcomes
ORDER BY quintile;