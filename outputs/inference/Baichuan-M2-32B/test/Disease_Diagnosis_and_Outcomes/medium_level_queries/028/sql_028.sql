WITH base_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate approximate age at admission using anchor_year and anchor_age
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
        -- Compute LOS in days
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'  -- Male patients
),
hf_admissions AS (
    SELECT
        bc.*,
        -- Identify admissions with HF diagnosis (ICD-10 codes starting with 'I50')
        MAX(CASE WHEN d.icd_code LIKE 'I50%' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_hf
    FROM base_cohort bc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON bc.subject_id = d.subject_id AND bc.hadm_id = d.hadm_id
    GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag, bc.age_at_admission, bc.los_days
    HAVING has_hf = 1  -- Keep only admissions with HF
),
age_filtered AS (
    SELECT *
    FROM hf_admissions
    WHERE age_at_admission BETWEEN 43 AND 53  -- Age 43-53 at admission
),
comorbidity_counts AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        -- Count distinct non-HF diagnoses per admission (ICD-10, excluding I50 codes)
        COUNT(DISTINCT CASE WHEN d.icd_code NOT LIKE 'I50%' AND d.icd_version = 10 THEN d.icd_code END) AS comorbidity_count
    FROM age_filtered af
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON af.subject_id = d.subject_id AND af.hadm_id = d.hadm_id
    GROUP BY af.subject_id, af.hadm_id
),
comorbidity_groups AS (
    SELECT
        cc.subject_id,
        cc.hadm_id,
        cc.comorbidity_count,
        -- Define comorbidity burden groups
        CASE
            WHEN cc.comorbidity_count BETWEEN 1 AND 2 THEN 'Low'
            WHEN cc.comorbidity_count BETWEEN 3 AND 4 THEN 'Medium'
            WHEN cc.comorbidity_count >= 5 THEN 'High'
            ELSE 'Unknown'
        END AS comorbidity_burden
    FROM comorbidity_counts cc
),
combined_data AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        af.hospital_expire_flag,
        af.los_days,
        cg.comorbidity_burden
    FROM age_filtered af
    INNER JOIN comorbidity_groups cg
        ON af.subject_id = cg.subject_id AND af.hadm_id = cg.hadm_id
),
final_data AS (
    SELECT
        cd.*,
        -- Assign LOS quartiles (Q1-Q4) using NTILE
        NTILE(4) OVER (ORDER BY cd.los_days) AS los_quartile
    FROM combined_data cd
)
-- Calculate mortality rate (%) stratified by LOS quartile and comorbidity burden
SELECT
    los_quartile,
    comorbidity_burden,
    COUNT(*) AS num_admissions,
    SUM(hospital_expire_flag) AS num_deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM final_data
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;