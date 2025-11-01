WITH respiratory_measurements AS (
    SELECT 
        c.stay_id,
        MAX(c.valuenum) AS max_resp_rate
    FROM 
        `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN 
        `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON c.itemid = d.itemid
    WHERE 
        d.label = 'Respiratory Rate'
        AND c.valuenum IS NOT NULL
    GROUP BY 
        c.stay_id
),
target_patients AS (
    SELECT 
        i.stay_id
    FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
        `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON p.subject_id = i.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 35 AND 45
)
SELECT 
    MIN(r.max_resp_rate) AS min_of_max_resp_rate
FROM 
    target_patients t
JOIN 
    respiratory_measurements r 
    ON t.stay_id = r.stay_id;