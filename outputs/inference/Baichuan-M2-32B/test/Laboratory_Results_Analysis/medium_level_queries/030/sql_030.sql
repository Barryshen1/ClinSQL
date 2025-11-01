WITH eligible_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        p.anchor_age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I21%'
),
first_admission_per_patient AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime
    FROM (
        SELECT 
            subject_id,
            hadm_id,
            admittime,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM eligible_admissions
    ) 
    WHERE rn = 1
),
troponin_tests AS (
    SELECT 
        f.subject_id,
        f.hadm_id,
        f.admittime,
        l.labevent_id,
        l.charttime,
        l.valuenum,
        l.valueuom,
        ROW_NUMBER() OVER (PARTITION BY f.hadm_id ORDER BY l.charttime) AS rn_lab
    FROM first_admission_per_patient f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON f.subject_id = l.subject_id AND f.hadm_id = l.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
    WHERE 
        d.label LIKE '%troponin T%' 
        AND (d.label LIKE '%high-sensitivity%' OR d.label LIKE '%hs%')
        AND LOWER(l.valueuom) LIKE '%ng/ml%'  -- Fixed unit check using labevents.valueuom
        AND l.valuenum IS NOT NULL
        AND l.valuenum > 0
),
first_troponin_per_admission AS (
    SELECT 
        subject_id,
        valuenum
    FROM troponin_tests
    WHERE rn_lab = 1
),
categorized_troponin AS (
    SELECT 
        subject_id,
        CASE 
            WHEN valuenum <= 0.014 THEN 'Normal'
            WHEN valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline'
            WHEN valuenum > 0.052 THEN 'Myocardial Injury'
        END AS category
    FROM first_troponin_per_admission
)
SELECT 
    category,
    COUNT(DISTINCT subject_id) AS num_patients,
    COUNT(DISTINCT subject_id) * 100.0 / (SELECT COUNT(DISTINCT subject_id) FROM categorized_troponin) AS percentage
FROM categorized_troponin
GROUP BY category
ORDER BY 
    CASE category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Myocardial Injury' THEN 3
    END;