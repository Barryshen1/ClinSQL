WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Comorbidity count: CHF, Diabetes, CKD
        (SELECT COUNT(DISTINCT dia.icd_code) 
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
         WHERE dia.hadm_id = adm.hadm_id
         AND (
             dia.icd_code LIKE 'I50%' OR dia.icd_code LIKE 'I110%' OR dia.icd_code LIKE 'I130%' 
             OR dia.icd_code LIKE 'I132%' OR dia.icd_code LIKE 'I255%' OR dia.icd_code LIKE 'I42%'
             OR dia.icd_code LIKE 'E10%' OR dia.icd_code LIKE 'E11%' OR dia.icd_code LIKE 'E13%'
             OR dia.icd_code LIKE 'N18%' OR dia.icd_code LIKE 'I1311%' OR dia.icd_code LIKE 'N19%'
             OR dia.icd_code LIKE 'N25%' OR dia.icd_code LIKE 'Z892%' OR dia.icd_code LIKE 'Z903%'
             OR dia.icd_code LIKE 'Z933%' OR dia.icd_code LIKE 'I130%' OR dia.icd_code LIKE 'I132%'
             OR dia.icd_code LIKE 'Z940%'
         )
        ) AS comorbidity_count,
        -- Flags for CKD and Diabetes
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia 
            WHERE dia.hadm_id = adm.hadm_id 
            AND (dia.icd_code LIKE 'N18%' OR dia.icd_code LIKE 'I1311%' OR dia.icd_code LIKE 'N19%'
                 OR dia.icd_code LIKE 'N25%' OR dia.icd_code LIKE 'Z892%' OR dia.icd_code LIKE 'Z903%'
                 OR dia.icd_code LIKE 'Z933%' OR dia.icd_code LIKE 'I130%' OR dia.icd_code LIKE 'I132%'
                 OR dia.icd_code LIKE 'Z940%')
        ) AS has_ckd,
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia 
            WHERE dia.hadm_id = adm.hadm_id 
            AND (dia.icd_code LIKE 'E10%' OR dia.icd_code LIKE 'E11%' OR dia.icd_code LIKE 'E13%')
        ) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 78 AND 88
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia 
            WHERE dia.hadm_id = adm.hadm_id 
            AND (dia.icd_code LIKE 'I21%' OR dia.icd_code LIKE 'I22%')
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia 
            WHERE dia.hadm_id = adm.hadm_id 
            AND (dia.icd_code LIKE 'R57%' OR dia.icd_code LIKE 'J96%')
        )
),
los_quartiles AS (
    SELECT 
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los,
        comorbidity_count,
        CASE 
            WHEN comorbidity_count <= 1 THEN 'Low'
            WHEN comorbidity_count = 2 THEN 'Medium'
            ELSE 'High'
        END AS comorbidity_burden,
        has_ckd,
        has_diabetes,
        NTILE(4) OVER (ORDER BY los) AS los_quartile
    FROM cohort
    WHERE los IS NOT NULL
)
SELECT 
    los_quartile,
    comorbidity_burden,
    COUNT(*) AS n_patients,
    -- Mortality rate with 95% CI (normal approximation)
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(AVG(hospital_expire_flag)) OVER () - 1.96 * SQRT(AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*)) AS mortality_ci_lower,
    AVG(AVG(hospital_expire_flag)) OVER () + 1.96 * SQRT(AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*)) AS mortality_ci_upper,
    AVG(CAST(has_ckd AS INT)) AS ckd_prevalence,
    AVG(CAST(has_diabetes AS INT)) AS diabetes_prevalence
FROM los_quartiles
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;