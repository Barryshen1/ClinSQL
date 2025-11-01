WITH age_calc AS (
    SELECT 
        adm.hadm_id,
        adm.subject_id,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_adm
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
),
primary_diagnosis AS (
    SELECT 
        hadm_id,
        icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1
),
troponin_initial AS (
    SELECT 
        le.hadm_id,
        le.valuenum AS troponin_t
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.label = 'Troponin T'
        AND le.valuenum IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id 
        ORDER BY le.charttime
    ) = 1
)
SELECT 
    MIN(troponin_t) AS min_troponin,
    MAX(troponin_t) AS max_troponin,
    APPROX_QUANTILES(troponin_t, 1000)[OFFSET(250)] AS p25,
    APPROX_QUANTILES(troponin_t, 1000)[OFFSET(500)] AS p50,
    APPROX_QUANTILES(troponin_t, 1000)[OFFSET(750)] AS p75
FROM age_calc ac
INNER JOIN primary_diagnosis pd 
    ON ac.hadm_id = pd.hadm_id
INNER JOIN troponin_initial ti
    ON ac.hadm_id = ti.hadm_id
WHERE 
    ac.gender = 'F'
    AND ac.age_at_adm BETWEEN 82 AND 92
    AND (
        (pd.icd_code LIKE 'R07.%' AND pd.icd_code NOT LIKE 'R07.0%')
        OR pd.icd_code LIKE 'I21.%'
        OR pd.icd_code LIKE 'I22.%'
    )
    AND ti.troponin_t > 0.01;