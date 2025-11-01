SELECT
    -- Assign categories based on the first hs-Troponin T value
    CASE
        WHEN ft.first_troponin_t_val < 0.014 THEN 'Normal (<0.014 ng/mL)'
        WHEN ft.first_troponin_t_val >= 0.014 AND ft.first_troponin_t_val < 0.04 THEN 'Borderline (0.014–<0.04 ng/mL)'
        WHEN ft.first_troponin_t_val >= 0.04 THEN 'Myocardial Injury (>=0.04 ng/mL)'
        ELSE 'Undetermined' -- Should not be reached if valuenum is not null
    END AS troponin_category,
    COUNT(DISTINCT ft.subject_id) AS patient_count
FROM
    (
        SELECT
            le.subject_id,
            le.valuenum AS first_troponin_t_val,
            ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime, le.labevent_id) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON le.subject_id = p.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 42 AND 52 -- Filter for female patients aged 42-52
            AND le.itemid = 51003 -- itemid for 'Troponin T, high sensitivity'
            AND le.valuenum IS NOT NULL -- Ensure a numeric result exists
            AND le.valueuom = 'ng/mL' -- Confirm the unit as specified in the question thresholds
    ) AS ft
WHERE
    ft.rn = 1 -- Select only the first measurement for each patient
GROUP BY
    troponin_category
ORDER BY
    CASE troponin_category
        WHEN 'Normal (<0.014 ng/mL)' THEN 1
        WHEN 'Borderline (0.014–<0.04 ng/mL)' THEN 2
        WHEN 'Myocardial Injury (>=0.04 ng/mL)' THEN 3
        ELSE 4 -- Place 'Undetermined' last if it ever occurs
    END;