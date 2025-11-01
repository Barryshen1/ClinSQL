WITH eligible_stays AS (
    SELECT 
        icu.stay_id,
        icu.los,
        -- Calculate age at ICU admission
        p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON icu.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        -- Filter for stroke diagnoses
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.hadm_id = icu.hadm_id
            AND (
                -- ICD-9: Hemorrhagic (430-432), infarction (433x1, 434x1), or unspecified (436)
                (diag.icd_version = 9 AND 
                    diag.icd_code IN ('430', '431', '432', '436') 
                    OR diag.icd_code LIKE '433%1' 
                    OR diag.icd_code LIKE '434%1'
                )
                OR
                -- ICD-10: All stroke types (I60-I64)
                (diag.icd_version = 10 AND 
                    (diag.icd_code LIKE 'I60%' 
                    OR diag.icd_code LIKE 'I61%' 
                    OR diag.icd_code LIKE 'I62%' 
                    OR diag.icd_code LIKE 'I63%' 
                    OR diag.icd_code LIKE 'I64%')
                )
            )
        )
)
-- Calculate median LOS for eligible ICU stays
SELECT 
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM eligible_stays
WHERE age_at_icu BETWEEN 35 AND 45;