WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 43 AND 53
),
acs_admissions AS (
    SELECT DISTINCT
        e.hadm_id,
        e.subject_id,
        e.admittime,
        e.dischtime,
        e.age_at_admission
    FROM eligible_admissions e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON e.hadm_id = d.hadm_id
    WHERE 
        d.icd_version = 10
        AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-5]')
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.subject_id,
        l.labevent_id,
        l.valuenum,
        l.valueuom,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
    WHERE 
        d.label LIKE '%Troponin T%'
        AND l.valueuom = 'ng/mL'
        AND l.valuenum IS NOT NULL
),
troponin_categories AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.age_at_admission,
        t.valuenum,
        CASE 
            WHEN t.valuenum < 0.01 THEN 'Normal'
            WHEN t.valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
            WHEN t.valuenum > 0.03 THEN 'Elevated'
            ELSE 'Unknown'
        END AS troponin_category
    FROM acs_admissions a
    INNER JOIN first_troponin t 
        ON a.hadm_id = t.hadm_id AND t.rn = 1
),
final_data AS (
    SELECT 
        troponin_category,
        COUNT(*) AS count,
        AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los
    FROM troponin_categories
    GROUP BY troponin_category
),
total AS (
    SELECT COUNT(*) AS total_count
    FROM troponin_categories
)
SELECT 
    f.troponin_category,
    f.count,
    (f.count * 100.0 / t.total_count) AS percentage,
    f.avg_los
FROM final_data f
CROSS JOIN total t
ORDER BY 
    CASE troponin_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4
    END;