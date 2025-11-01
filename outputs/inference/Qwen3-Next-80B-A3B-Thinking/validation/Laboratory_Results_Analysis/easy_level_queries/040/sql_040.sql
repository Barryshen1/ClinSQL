WITH female_dka_admissions AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON d.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE d_icd.long_title LIKE '%ketoacidosis%'
        AND p.gender = 'F'
),
peak_glucose AS (
    SELECT l.hadm_id, MAX(l.valuenum) AS peak
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN female_dka_admissions f ON l.hadm_id = f.hadm_id
    WHERE l.itemid = 50809
    GROUP BY l.hadm_id
),
ranked AS (
    SELECT peak,
           ROW_NUMBER() OVER (ORDER BY peak) AS rn,
           COUNT(*) OVER () AS total
    FROM peak_glucose
)
SELECT AVG(peak) AS median_peak_glucose
FROM ranked
WHERE rn IN (FLOOR((total + 1)/2), CEIL((total + 1)/2));