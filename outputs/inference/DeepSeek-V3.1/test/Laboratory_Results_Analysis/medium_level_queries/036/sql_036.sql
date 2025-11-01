WITH ami_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 77 AND 87
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%')
),
first_troponin_time AS (
    SELECT
        aa.hadm_id,
        MIN(le.charttime) AS first_charttime
    FROM ami_admissions aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON aa.hadm_id = le.hadm_id AND aa.subject_id = le.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.loinc_code = '6598-7'
        AND le.valuenum IS NOT NULL
        AND le.charttime >= aa.admittime
    GROUP BY aa.hadm_id
),
first_troponin_value AS (
    SELECT
        aa.subject_id,
        aa.hadm_id,
        le.valuenum AS troponin_value
    FROM ami_admissions aa
    INNER JOIN first_troponin_time ftt
        ON aa.hadm_id = ftt.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON aa.hadm_id = le.hadm_id 
           AND aa.subject_id = le.subject_id 
           AND ftt.first_charttime = le.charttime
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.loinc_code = '6598-7'
        AND le.valuenum IS NOT NULL
)
SELECT
    CASE
        WHEN troponin_value <= 14 THEN 'Normal'
        WHEN troponin_value BETWEEN 15 AND 19 THEN 'Borderline'
        WHEN troponin_value >= 20 THEN 'Myocardial injury'
    END AS category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM first_troponin_value
GROUP BY category
ORDER BY category;