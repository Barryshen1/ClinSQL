WITH target_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 36 AND 46
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                (icd_version = 9 AND icd_code BETWEEN '410' AND '414.99') 
                OR 
                (icd_version = 10 AND icd_code BETWEEN 'I20' AND 'I25.9')
        )
),
first_troponin AS (
    SELECT 
        lab.subject_id,
        lab.hadm_id,
        lab.charttime,
        lab.valuenum,
        SAFE_CAST(lab.ref_range_upper AS FLOAT64) AS ref_range_upper_num
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN target_admissions ta
        ON lab.hadm_id = ta.hadm_id
    WHERE lab.itemid = 50911  -- High-sensitivity Troponin T
),
ranked_troponin AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM first_troponin
),
initial_above_uln AS (
    SELECT 
        valuenum AS initial_troponin_value
    FROM ranked_troponin
    WHERE 
        rn = 1 
        AND ref_range_upper_num IS NOT NULL
        AND valuenum > ref_range_upper_num
),
percentiles AS (
    SELECT 
        APPROX_QUANTILES(initial_troponin_value, 4) AS quantiles
    FROM initial_above_uln
)
SELECT 
    quantiles[OFFSET(0)] AS min_value,
    quantiles[OFFSET(1)] AS p25,
    quantiles[OFFSET(2)] AS p50,
    quantiles[OFFSET(3)] AS p75,
    quantiles[OFFSET(4)] AS max_value
FROM percentiles;