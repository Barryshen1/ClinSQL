WITH acs_patients AS (
    SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON p.subject_id = d.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age = 57
        AND (
            (d.icd_version = 9 AND diag.icd_code LIKE '410%') OR
            (d.icd_version = 9 AND diag.icd_code LIKE '411%') OR
            (d.icd_version = 10 AND diag.icd_code LIKE 'I21%') OR
            (d.icd_version = 10 AND diag.icd_code LIKE 'I22%') OR
            (d.icd_version = 10 AND diag.icd_code = 'I24.0') OR
            (d.icd_version = 10 AND diag.icd_code = 'I20.0')
        )
),
troponin_labs AS (
    SELECT l.subject_id, l.hadm_id, l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
        ON l.itemid = li.itemid
    WHERE li.itemid IN (51003, 50911)  -- Troponin T and I
        AND l.valuenum IS NOT NULL
)
SELECT acs.subject_id, acs.hadm_id, MIN(t.valuenum) AS min_troponin
FROM acs_patients acs
INNER JOIN troponin_labs t
    ON acs.subject_id = t.subject_id AND acs.hadm_id = t.hadm_id
GROUP BY acs.subject_id, acs.hadm_id;