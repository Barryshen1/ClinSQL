WITH first_hstnt AS (
    SELECT 
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 50911
)
SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS p25,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS p75,
    MIN(valuenum) AS min_val,
    MAX(valuenum) AS max_val
FROM (
    SELECT 
        f.valuenum
    FROM first_hstnt f
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON f.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
    WHERE f.rn = 1
        AND pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 59 AND 69
        AND f.valuenum > 0.014
) AS filtered;